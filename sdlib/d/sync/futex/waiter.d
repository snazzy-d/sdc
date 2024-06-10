module d.sync.futex.waiter;

import d.sync.atomic;
import d.sync.futex.futex;

import core.stdc.errno_;

struct FutexWaiter {
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
