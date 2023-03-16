module d.sync.mutex;

import d.sync.waiter;

import sdc.intrinsics;

import sys.posix.sched;

struct Mutex {
private:
	import d.sync.atomic;
	Atomic!size_t word;

	enum size_t LockBit = 0x01;
	enum size_t QueueLockBit = 0x02;
	enum size_t ThreadDataMask = ~(LockBit | QueueLockBit);

public:
	void lock() shared {
		// No operation done after the lock is taken can be reordered before.
		size_t expected = 0;
		if (likely(word.casWeak(expected, LockBit, MemoryOrder.Acquire))) {
			return;
		}

		lockSlow();
	}

	bool tryLock() shared {
		size_t current = 0;
		if (likely(word.casWeak(current, LockBit, MemoryOrder.Acquire))) {
			return true;
		}

		if (current & LockBit) {
			return false;
		}

		assert(!(current & QueueLockBit), "Queue lock held while unlocked!");
		return word.casWeak(current, current | LockBit, MemoryOrder.Acquire);
	}

	bool isHeld() {
		return (cast(shared(Mutex)*) &this).isHeld();
	}

	bool isHeld() shared {
		return (word.load() & LockBit) != 0;
	}

	void unlock() shared {
		// No operation done before the lock is freed can be reordered after.
		size_t expected = LockBit;
		if (likely(word.casWeak(expected, 0, MemoryOrder.Release))) {
			return;
		}

		unlockSlow(Fairness.Unfair);
	}

	void unlockFairly() shared {
		// No operation done before the lock is freed can be reordered after.
		size_t expected = LockBit;
		if (likely(word.casWeak(expected, 0, MemoryOrder.Release))) {
			return;
		}

		unlockSlow(Fairness.Fair);
	}

private:
	enum Handoff {
		None,
		Barging,
		Direct,
	}

	/**
	 * When the lock is contended, we create a linked list
	 * representing the threads waiting on the lock.
	 *
	 * The linked list loops around (the tail points to the head)
	 * and the mutex itself points ot the tail, such as
	 * tail.next == head.
	 */
	struct ThreadData {
		// Covered by the queue lock.
		ThreadData* next;

	shared: // FIXME: shared colon block aparently isn't working.
		shared Waiter waiter;
		shared Atomic!uint handoff;
	}

	static ThreadData threadData;

	void lockSlow() shared {
		// Trusting WTF::WordLock on that one...
		enum SpinLimit = 40;

		uint spinCount = 0;
		ThreadData* me = null;

		while (true) {
			auto current = word.load(MemoryOrder.Relaxed);

			// If the lock if free, we try to barge in.
			if (!(current & LockBit)) {
				assert(!(current & QueueLockBit),
				       "Queue lock held while unlocked!");

				if (word.casWeak(current, current | LockBit,
				                 MemoryOrder.Acquire)) {
					// We got the lock, VICTORY !
					return;
				}

				continue;
			}

			assert(current & LockBit, "Lock not held!");

			// If nobody's parked...
			if (!(current & ThreadDataMask) && spinCount < SpinLimit) {
				spinCount++;
				sched_yield();
				continue;
			}

			// Prepare ourselves to be queued.
			if (me is null) {
				me = &threadData;
			}

			// Ok, we need to park. Take the queue lock.
			if ((current & QueueLockBit) || !word
				    .casWeak(current, current | QueueLockBit,
				             MemoryOrder.Acquire)) {
				sched_yield();
				continue;
			}

			// Add ourselves in the queue.
			assert(me.next is null, "This thread is already queued!");

			auto tail = cast(ThreadData*) (current & ThreadDataMask);
			tail = tail is null ? me : tail;
			me.next = tail.next;
			tail.next = me;

			// Setup ourselves up for handoff.
			me.handoff.store(Handoff.None, MemoryOrder.Release);

			// Now we store the updated head. Note that this will release the
			// queue lock too, but it's okay, by now we are in the queue.
			word.store(LockBit | cast(size_t) me, MemoryOrder.Release);

			// Wait for the control to be handed back to us.
			uint handoff;
			while ((handoff = me.handoff.load(MemoryOrder.Acquire))
				       == Handoff.None) {
				me.waiter.block();

				// FIXME: Dequeue ourselves in case of timeout.
			}

			switch (handoff) {
				case Handoff.Direct:
					// We are done.
					assert(word.load(MemoryOrder.Relaxed) & LockBit,
					       "Lock not held!");
					return;

				case Handoff.Barging:
					// Just try to take the lock again.
					continue;

				default:
					assert(0, "Invalid handoff value!");
			}
		}
	}

	// FIXME: Crashing for some reason.
	enum Fairness /* : bool */ {
		Unfair = 0,
		Fair = 1,
	}

	void unlockSlow(Fairness fair) shared {
		while (true) {
			auto current = word.load(MemoryOrder.Relaxed);
			assert(current & LockBit, "Lock not held!");

			// If nobody is parked, just unlock.
			if (current == LockBit) {
				if (word.casWeak(current, 0, MemoryOrder.Release)) {
					return;
				}

				continue;
			}

			// If the queue is locked, just wait.
			if (current & QueueLockBit) {
				sched_yield();
				continue;
			}

			// We must have another thread waiting. Lock the queue
			// and release the next thread in line.
			if (word.casWeak(current, current | QueueLockBit,
			                 MemoryOrder.Acquire)) {
				break;
			}
		}

		auto current = word.load(MemoryOrder.Relaxed);
		assert(current & LockBit, "Lock not held!");
		assert(current & QueueLockBit, "Queue lock not held!");

		auto tail = cast(ThreadData*) (current & ThreadDataMask);
		assert(tail !is null, "Queue is empty!");

		// Pop the head.
		auto head = tail.next;
		tail.next = head.next;

		/**
		 * As we update the tail, we also release the queue lock.
		 * The lock itself is kept is the fair case, or unlocked if
		 * fairness is not a concern.
		 */
		auto newTail = (head == tail) ? 0 : cast(size_t) tail;
		word.store(newTail | fair, MemoryOrder.Release);

		// Make sure our bit trickery remains valid.
		static assert((Handoff.Barging + Fairness.Fair) == Handoff.Direct);

		// Wake up the blocked thread.
		head.next = null;
		head.handoff.store(Handoff.Barging + fair, MemoryOrder.Release);
		head.waiter.wakeup();
	}
}

unittest locking {
	static runThread(void* delegate() dg) {
		static struct Delegate {
			void* ctx;
			void* function(void*) fun;
		}

		auto x = *(cast(Delegate*) &dg);

		import d.rt.thread;
		pthread_t tid;
		auto r = pthread_create(&tid, null, x.fun, x.ctx);
		assert(r == 0, "Failed to create thread!");

		return tid;
	}

	import d.sync.atomic;
	shared Mutex mutex;
	shared Atomic!uint state;

	void* run1() {
		assert(state.load() == 0);

		mutex.lock();
		assert(mutex.word.load() == 0x01, "Invalid mutext state!");
		state.store(1);
		mutex.unlock();

		while (state.load() != 2) {
			sched_yield();
		}

		return null;
	}

	void* run2() {
		while (state.load() != 1) {
			sched_yield();
		}

		assert(state.load() == 1);

		mutex.lock();
		assert(mutex.word.load() == 0x01, "Invalid mutext state!");
		state.store(2);
		mutex.unlock();

		return null;
	}

	auto t1 = runThread(run1);
	auto t2 = runThread(run2);

	void* ret;

	import d.rt.thread;
	pthread_join(t1, &ret);
	pthread_join(t2, &ret);

	assert(mutex.word.load() == 0x00, "Invalid mutext state!");

	shared Atomic!uint count;
	void* hammer() {
		foreach (i; 0 .. 1024) {
			mutex.lock();
			count.fetchAdd(1);
			if ((i >> 1) & 0x03) {
				mutex.unlock();
			} else {
				mutex.unlockFairly();
			}
		}

		return null;
	}

	pthread_t[1024] ts;
	foreach (i; 0 .. ts.length) {
		ts[i] = runThread(hammer);
	}

	foreach (i; 0 .. ts.length) {
		pthread_join(ts[i], &ret);
	}

	assert(mutex.word.load() == 0x00, "Invalid mutext state!");
	assert(count.load() == 1024 * 1024);
}

extern(C) int sleep(int);

unittest fairness {
	static runThread(void* delegate() dg) {
		static struct Delegate {
			void* ctx;
			void* function(void*) fun;
		}

		auto x = *(cast(Delegate*) &dg);

		import d.rt.thread;
		pthread_t tid;
		auto r = pthread_create(&tid, null, x.fun, x.ctx);
		assert(r == 0, "Failed to create thread!");

		return tid;
	}

	enum ThreadCount = 8;

	import d.sync.atomic;
	uint[ThreadCount] counts;
	shared Mutex mutex;
	shared Atomic!uint keepGoing;

	auto run(uint i) {
		void* fun() {
			auto index = i;
			while (keepGoing.load() != 0) {
				mutex.lock();
				counts[index]++;
				mutex.unlockFairly();
			}

			return null;
		}

		return runThread(fun);
	}

	// Start the threads.
	keepGoing.store(true);
	mutex.lock();

	import d.rt.thread;
	pthread_t[ThreadCount] ts;
	foreach (i; 0 .. ThreadCount) {
		ts[i] = run(i);
	}

	mutex.unlock();

	sleep(1);
	keepGoing.store(false);

	import core.stdc.stdio;
	printf("Fairness results:\n");

	foreach (i; 0 .. ThreadCount) {
		void* ret;
		pthread_join(ts[i], &ret);
		printf("\t%4d => %16u\n", i, counts[i]);
	}
}
