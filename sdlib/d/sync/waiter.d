module d.sync.waiter;

import d.sync.atomic;
import d.sync.futex;

import core.stdc.errno_;

struct Waiter {
	Atomic!uint wakeupCount;

	bool block( /* TODO: timeout */ ) shared {
		while (true) {
			auto c = wakeupCount.load();
			while (c > 0) {
				if (wakeupCount.casWeak(c, c - 1)) {
					// We consumed a wake up.
					return true;
				}
			}

			assert(c == 0, "Failed to consume wake up!");

			auto err = futex_wait(&wakeupCount, 0);
			switch (err) {
				case 0, -EINTR, -EWOULDBLOCK:
					continue;

				case -ETIMEDOUT:
					return false;

				default:
					assert(0, "futex operation failed!");
			}
		}

		// FIXME: Control flow analysis should be able
		// to figure this one out.
		assert(0, "unreachable");
	}

	void wakeup() shared {
		if (wakeupCount.fetchAdd(1) == 0) {
			poke();
		}
	}

	void poke() shared {
		auto err = futex_wake_one(&wakeupCount);
		assert(err == 0, "futex operation failed!");
	}
}
