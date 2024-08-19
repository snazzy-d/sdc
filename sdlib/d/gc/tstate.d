module d.gc.tstate;

import sdc.intrinsics;

struct ThreadState {
private:
	import d.sync.atomic;
	shared Atomic!size_t state;

	enum StoppedFlag = 0x01;
	enum StopRequestedFlag = 0x02;
	enum BusyIncrement = 0x04;

	enum MustStop = BusyIncrement | StopRequestedFlag;

public:
	bool isRunning() {
		return !isStopped();
	}

	bool isStopped() {
		return (state.load() & StoppedFlag) != 0;
	}

	bool stopRequested() {
		return (state.load() & StopRequestedFlag) != 0;
	}

	void enterBusyState() {
		assert(isRunning());
		state.fetchAdd(BusyIncrement);
	}

	bool exitBusyState() {
		size_t s = BusyIncrement;
		if (likely(state.casWeak(s, 0))) {
			return false;
		}

		return exitBusyStateSlow(s);
	}

	void suspend() {
		// Make sure the thread is running and not too busy.
		auto s = state.load();
		assert(s == 0 || s == MustStop);

		state.store(0);
	}

private:
	bool exitBusyStateSlow(size_t s) {
		while (true) {
			assert(s >= BusyIncrement);
			assert((s & StoppedFlag) == 0);

			if (s == MustStop) {
				suspend();
				return true;
			}

			if (state.casWeak(s, s - BusyIncrement)) {
				return false;
			}
		}
	}
}
