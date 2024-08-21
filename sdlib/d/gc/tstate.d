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

struct ThreadState {
private:
	import d.sync.atomic;
	shared Atomic!size_t state;

	enum StatusMask = 0x03;
	enum BusyIncrement = 0x04;

	enum RunningState = SuspendState.None;
	enum SuspendedState = SuspendState.Suspended;

	enum MustSuspendState = BusyIncrement | SuspendState.Delayed;

public:
	@property
	auto suspendState() {
		return cast(SuspendState) (state.load() & StatusMask);
	}

	@property
	bool busy() {
		return state.load() >= BusyIncrement;
	}

	void enterBusyState() {
		auto s = state.fetchAdd(BusyIncrement);
		assert((s & StatusMask) != SuspendState.Suspended);
	}

	bool exitBusyState() {
		size_t s = BusyIncrement;
		if (likely(state.casWeak(s, RunningState))) {
			return false;
		}

		return exitBusyStateSlow(s);
	}

	void suspend() {
		// Make sure the thread is running and not too busy.
		auto s = state.load();
		assert(s == RunningState || s == MustSuspendState);

		// Stop the thread.
		state.store(SuspendedState);

		// FIXME: Actually stop the thread.

		// Resume execution at the end of suspend.
		state.store(RunningState);
	}

private:
	bool exitBusyStateSlow(size_t s) {
		while (true) {
			assert(s >= BusyIncrement);
			assert((s & StatusMask) != SuspendState.Suspended);

			if (s == MustSuspendState) {
				suspend();
				return true;
			}

			if (state.casWeak(s, s - BusyIncrement)) {
				return false;
			}
		}
	}
}
