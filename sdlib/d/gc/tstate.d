module d.gc.tstate;

import sdc.intrinsics;

enum SuspendState {
	// The thread is running as usual.
	None,
	// A signal has been sent to the thread that it'll need to suspend.
	Signaled,
	// The suspend was delayed, because the thread was busy.
	Delayed,
	// The thread is suspended.
	Suspended,
}

static auto status(size_t v) {
	enum StatusMask = 0x03;
	return cast(SuspendState) (v & StatusMask);
}

struct ThreadState {
private:
	import d.sync.atomic;
	shared Atomic!size_t state;

	enum BusyIncrement = 0x04;

	enum RunningState = SuspendState.None;
	enum SignaledState = SuspendState.Signaled;
	enum SuspendedState = SuspendState.Suspended;

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

	void sendSignal() {
		auto s = state.load();
		while (true) {
			auto n = s | SuspendState.Signaled;

			assert(status(s) == SuspendState.None);
			assert(status(n) == SuspendState.Signaled);

			if (state.casWeak(s, n)) {
				break;
			}
		}
	}

	bool recieveSignal() {
		auto s = state.fetchAdd(1);
		assert(status(s) == SuspendState.Signaled);

		// The thread is not busy, put it to sleep!
		if (s != SignaledState) {
			return false;
		}

		suspend(s);
		return true;
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

private:
	bool exitBusyStateSlow(size_t s) {
		while (true) {
			assert(s >= BusyIncrement);
			assert(status(s) != SuspendState.Suspended);

			if (s == MustSuspendState) {
				suspend(s);
				return true;
			}

			if (state.casWeak(s, s - BusyIncrement)) {
				return false;
			}
		}
	}

	void suspend(size_t s) {
		// Make sure the thread is running and not too busy.
		assert(s == SignaledState || s == MustSuspendState);

		// Stop the thread.
		state.store(SuspendedState);

		// Suspend this thread.
		import d.gc.global;
		gState.suspendThread();

		// Resume execution.
		state.store(RunningState);
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
		// Check simply busy/unbusy state transtion.
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
	checkForState(SuspendState.Signaled);
}

unittest signal {
	ThreadState s;

	void check(SuspendState ss, bool busy) {
		assert(s.suspendState == ss);
		assert(s.busy == busy);
	}

	// Check init state.
	check(SuspendState.None, false);

	// Simple signal.
	s.sendSignal();
	check(SuspendState.Signaled, false);

	assert(s.recieveSignal());
	check(SuspendState.None, false);

	// Signal while busy.
	s.sendSignal();
	check(SuspendState.Signaled, false);

	s.enterBusyState();
	s.enterBusyState();
	check(SuspendState.Signaled, true);

	assert(!s.recieveSignal());
	check(SuspendState.Delayed, true);

	assert(!s.exitBusyState());
	check(SuspendState.Delayed, true);

	assert(s.exitBusyState());
	check(SuspendState.None, false);
}

unittest suspend {
	ThreadState state;

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

	void* runSuspend() {
		// Wait for the main thread to signal.
		while (state.suspendState != SuspendState.Signaled) {
			import sys.posix.sched;
			sched_yield();
		}

		auto suspended = state.recieveSignal();
		assert(suspended);

		return null;
	}

	// Stop the world!
	import d.thread;
	__sd_thread_stop_the_world();

	// Start or ginea pig thread.
	auto tid = runThread(runSuspend);

	// Signal the thread.
	state.sendSignal();

	// Wait for the thread to be suspended.
	while (state.suspendState != SuspendState.Suspended) {
		import sys.posix.sched;
		sched_yield();
	}

	// Resume the executation and check the thread restarts.
	__sd_thread_restart_the_world();

	while (state.suspendState != SuspendState.None) {
		import sys.posix.sched;
		sched_yield();
	}

	void* ret;

	import core.stdc.pthread;
	pthread_join(tid, &ret);
}
