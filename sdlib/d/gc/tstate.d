module d.gc.tstate;

import sdc.intrinsics;

enum SuspendState {
	// The thread is running as usual.
	None,
	// The thread has been notified that it'll need to suspend.
	Notified,
	// The suspend was delayed, because the thread was busy.
	Delayed,
	// The thread is suspended.
	Suspended,
	// The thread is in the process of resuming operations.
	Resumed,
	// The thread is detached. The GC won't stop it.
	Detached,
}

static auto status(size_t v) {
	enum StatusMask = ThreadState.BusyIncrement - 1;
	return cast(SuspendState) (v & StatusMask);
}

struct ThreadState {
private:
	import d.sync.atomic;
	shared Atomic!size_t state;

	enum BusyIncrement = 0x08;

	enum RunningState = SuspendState.None;
	enum NotifiedState = SuspendState.Notified;
	enum SuspendedState = SuspendState.Suspended;
	enum DelayedState = SuspendState.Delayed;
	enum ResumedState = SuspendState.Resumed;

	enum MustSuspendState = BusyIncrement | SuspendState.Delayed;

public:
	@property
	auto suspendState() {
		return status(state.load());
	}

	@property
	bool busy() {
		return state.load() >= BusyIncrement;
	}

	void notify() {
		auto s = state.load();
		while (true) {
			auto n = s + SuspendState.Notified;

			assert(status(s) == SuspendState.None);
			assert(status(n) == SuspendState.Notified);

			if (state.casWeak(s, n)) {
				break;
			}
		}
	}

	void detach() {
		auto s = state.load();
		while (true) {
			auto n = s - SuspendState.Notified + SuspendState.Detached;

			assert(status(s) == SuspendState.Notified);
			assert(status(n) == SuspendState.Detached);

			if (state.casWeak(s, n)) {
				break;
			}
		}
	}

	bool onSuspendSignal() {
		auto s = state.load();

		while (true) {
			// If the thread isn't busy, we can suspend right away.
			if (s == NotifiedState) {
				import d.gc.signal;
				suspendThreadFromSignal(&this);

				return true;
			}

			if (status(s) != SuspendState.Notified) {
				// This signal is spurious or no longer useful.
				return false;
			}

			// The thread is busy, delay suspension.
			auto n = s + SuspendState.Notified;
			assert(status(n) == SuspendState.Delayed);

			if (state.casWeak(s, n)) {
				return false;
			}
		}
	}

	void resume() {
		auto s = state.load();
		while (true) {
			auto n = s + SuspendState.Notified;

			assert(status(s) == SuspendState.Suspended);
			assert(status(n) == SuspendState.Resumed);

			if (state.casWeak(s, n)) {
				break;
			}
		}
	}

	void onResumeSignal() {
		size_t s = ResumedState;
		while (true) {
			if (state.casWeak(s, RunningState)) {
				break;
			}

			if (s != ResumedState) {
				// This signal is spurious or no longer useful.
				return;
			}
		}
	}

	void enterBusyState() {
		auto s = state.fetchAdd(BusyIncrement);
		assert(status(s) != SuspendState.Suspended);
	}

	bool exitBusyState() {
		size_t s = BusyIncrement;
		if (likely(state.casWeak(s, RunningState))) {
			return false;
		}

		return exitBusyStateSlow(s);
	}

package:
	void markSuspended() {
		// The status to delayed because of the fetchAdd in onSuspendSignal.
		auto s = state.load();
		assert(s == NotifiedState || s == MustSuspendState);

		state.store(SuspendedState);
	}

private:
	bool exitBusyStateSlow(size_t s) {
		while (true) {
			assert(s >= BusyIncrement);
			assert(status(s) != SuspendState.Suspended);

			if (s == MustSuspendState) {
				import d.gc.signal;
				suspendThreadDelayed(&this);

				return true;
			}

			if (state.casWeak(s, s - BusyIncrement)) {
				return false;
			}
		}
	}
}

unittest busy {
	ThreadState s;

	void check(SuspendState ss, bool busy) {
		assert(s.suspendState == ss);
		assert(s.busy == busy);
	}

	// Check init state.
	check(SuspendState.None, false);

	void checkForState(SuspendState ss) {
		// Check simply busy/unbusy state transition.
		s.state.store(ss);
		check(ss, false);

		s.enterBusyState();
		check(ss, true);

		assert(!s.exitBusyState());
		check(ss, false);

		// Check nesting busy states.
		s.enterBusyState();
		s.enterBusyState();
		check(ss, true);

		assert(!s.exitBusyState());
		check(ss, true);

		assert(!s.exitBusyState());
		check(ss, false);
	}

	checkForState(SuspendState.None);
	checkForState(SuspendState.Notified);
}

unittest suspend {
	import d.gc.signal;
	setupSignals();

	static runThread(void* delegate() dg) {
		static struct Delegate {
			void* ctx;
			void* function(void*) fun;
		}

		auto x = *(cast(Delegate*) &dg);

		import core.stdc.pthread;
		pthread_t tid;
		auto r = pthread_create(&tid, null, x.fun, x.ctx);
		assert(r == 0, "Failed to create thread!");

		return tid;
	}

	// Make sure to use the state from the thread cache
	// so signal can find it back when needed.
	import d.gc.tcache;
	ThreadCache* tc = &threadCache;

	// Depending on the environment the thread runs in,
	// this may not have been initialized.
	import core.stdc.pthread;
	tc.self = pthread_self();

	ThreadState* s = &tc.state;
	scope(exit) {
		assert(s.state.load() == 0, "Invalid leftover state!");
	}

	import d.sync.atomic;
	shared Atomic!uint resumeCount;

	import d.sync.mutex;
	shared Mutex mutex;
	uint step = 0;
	bool mustStop = false;

	void moveToNextStep() {
		mutex.lock();
		scope(exit) mutex.unlock();

		step++;
	}

	void setMustStop() {
		mutex.lock();
		scope(exit) mutex.unlock();

		mustStop = true;
	}

	void* autoResume() {
		mutex.lock();
		scope(exit) mutex.unlock();
		assert(step == 0, "Unexpected step when starting.");

		uint nextStep = 1;

		while (!mustStop) {
			// Wait for the main thread to be suspended.
			if (s.suspendState != SuspendState.Suspended) {
				// Make sure we leave the opportunity to update mustStop!
				mutex.unlock();
				scope(exit) mutex.lock();

				import core.stdc.sched;
				sched_yield();
				continue;
			}

			// It is suspend, resume it.
			resumeCount.fetchAdd(1);

			tc.state.resume();

			import d.gc.signal;
			resumeThread(tc);

			// Wait for the next test.
			bool hasReachedNextStep() {
				return step >= nextStep;
			}

			mutex.waitFor(hasReachedNextStep);
			nextStep = step + 1;
		}

		return null;
	}

	auto autoResumeThreadID = runThread(autoResume);
	scope(exit) {
		setMustStop();

		void* ret;
		pthread_join(autoResumeThreadID, &ret);
	}

	void check(SuspendState ss, bool busy, uint suspendCount) {
		assert(s.suspendState == ss);
		assert(s.busy == busy);
		assert(resumeCount.load() == suspendCount);
	}

	// Check init state.
	check(SuspendState.None, false, 0);

	// Check that spurious signals are ignored.
	assert(!s.onSuspendSignal());
	check(SuspendState.None, false, 0);

	// Simple signal.
	s.notify();
	check(SuspendState.Notified, false, 0);

	assert(s.onSuspendSignal());
	check(SuspendState.None, false, 1);

	// Check repeated signals are ignored.
	assert(!s.onSuspendSignal());
	check(SuspendState.None, false, 1);

	moveToNextStep();

	// Check that spurious signals are ignored.
	assert(!s.onSuspendSignal());
	check(SuspendState.None, false, 1);

	// Signal while busy.
	s.notify();
	check(SuspendState.Notified, false, 1);

	s.enterBusyState();
	s.enterBusyState();
	check(SuspendState.Notified, true, 1);

	assert(!s.onSuspendSignal());
	check(SuspendState.Delayed, true, 1);

	// Check repeated signals are ignored.
	assert(!s.onSuspendSignal());
	check(SuspendState.Delayed, true, 1);

	assert(!s.exitBusyState());
	check(SuspendState.Delayed, true, 1);

	assert(s.exitBusyState());
	check(SuspendState.None, false, 2);
	moveToNextStep();
}
