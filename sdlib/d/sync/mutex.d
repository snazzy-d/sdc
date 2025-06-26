module d.sync.mutex;

import d.sync.waiter;

import sdc.intrinsics;

import core.stdc.sched;

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

		unlockSlowUnfair();
	}

	void unlockFairly() shared {
		// No operation done before the lock is freed can be reordered after.
		size_t expected = LockBit;
		if (likely(word.casWeak(expected, 0, MemoryOrder.Release))) {
			return;
		}

		unlockSlowFair();
	}

	bool waitFor(bool delegate() condition) shared {
		assert((&this).isHeld(), "Mutex not held!");

		while (true) {
			if (condition()) {
				return true;
			}

			// FIXME: In case of timeout, we want to return false.
			//        At the moment, timeouts are not supported.
			WaitParams wp;
			wp.condition = condition;
			unlockAndWait(&wp);
		}
	}

	/**
	 * /!\: This will reset the state of the mutex.
	 *      If it was locked, it is now unlocked.
	 *      If there were thread witing for it, they are probably
	 *      lost forever.
	 *      This method is almost certainly not what you want to use.
	 */
	void __clear() shared {
		word.store(0);
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
		WaitParams* waitParams;

		ThreadData* next;
		ThreadData* skip;

		shared Waiter waiter;

		bool isEquivalentTo(const WaitParams* other) const {
			return waitParams.isEquivalentTo(other);
		}

		bool isEquivalentTo(const ThreadData* other) const {
			return isEquivalentTo(other.waitParams);
		}

		bool isLock() const {
			return waitParams.isLock();
		}

		bool isCondition() const {
			return waitParams.isCondition();
		}

		ThreadData* skipForward() {
			auto current = &this;

			auto s = current.skip;
			if (s is null) {
				return current;
			}

			while (s.skip !is null) {
				auto last = current;
				current = s;
				s = s.skip;

				// We update the skip list as we travel it so we can recompute
				// it faster once we pop td.
				last.skip = s;
			}

			// Make sure to skip the whole list at once next time.
			skip = s;

			assert(s !is null && s.skip is null);
			return s;
		}

		void updateSkip() {
			assert(next !is &this, "Tail's skip must remain null!");

			if (isEquivalentTo(next)) {
				// Leapfrog one hop if possible.
				skip = next.skip is null ? next : next.skip;
			}
		}
	}

	static ThreadData threadData;

	struct WaitParams {
		shared Atomic!uint handoff;

		bool delegate() condition;

		static bool dgCmp(bool delegate() a, bool delegate() b) {
			static union U {
				bool delegate() c;
				size_t[2] s;
			}

			U u1, u2;
			u1.c = a;
			u2.c = b;

			return u1.s[0] == u2.s[0] && u1.s[1] == u2.s[1];
		}

		bool isEquivalentTo(const WaitParams* other) const {
			return dgCmp(condition, other.condition);
		}

		bool isLock() const {
			bool delegate() nothing;
			return dgCmp(condition, nothing);
		}

		bool isCondition() const {
			bool delegate() nothing;
			return !dgCmp(condition, nothing);
		}
	}

	void lockSlow() shared {
		// Trusting WTF::WordLock on that one...
		enum SpinLimit = 40;
		uint spinCount = 0;

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

			WaitParams wp;

			// If we can, try try to register atomically.
			if (current == LockBit) {
				if (word.casWeak(current, selfEnqueue(&wp) | LockBit,
				                 MemoryOrder.Release)) {
					goto Handoff;
				}

				continue;
			}

			// We cannot register atomically, take the queue lock.
			if ((current & QueueLockBit) || !word
				    .casWeak(current, current | QueueLockBit,
				             MemoryOrder.Acquire)) {
				sched_yield();
				continue;
			}

			// Make sure we do have the queue lock.
			assert(word.load() & QueueLockBit, "Queue lock not acquired!");

			// Now we store the updated head. Note that this will release the
			// queue lock too, but it's okay, by now we are in the queue.
			word.store(enqueueLock(current, &wp) | LockBit,
			           MemoryOrder.Release);

		Handoff:
			if (waitForHandoff() == Handoff.Direct) {
				assert((&this).isHeld(), "Lock not held!");
				return;
			}
		}
	}

	static uint waitForHandoff() {
		auto me = &threadData;
		auto wp = &me.waitParams;

		// Wait for the control to be handed back to us.
		uint handoff;
		while ((handoff = wp.handoff.load(MemoryOrder.Acquire))
			       == Handoff.None) {
			me.waiter.block();

			// FIXME: Dequeue ourselves in case of timeout.
		}

		assert(handoff == Handoff.Direct || handoff == Handoff.Barging,
		       "Invalid handoff value!");
		return handoff;
	}

	void unlockAndWait(WaitParams* wp) shared {
		unlockSlowUnfair(wp);

		if (waitForHandoff() == Handoff.Barging) {
			lock();
		}

		assert((&this).isHeld(), "Lock not held!");
	}

	void unlockSlowUnfair(WaitParams* wp = null) shared {
		unlockSlowImpl!false(wp);
	}

	void unlockSlowFair() shared {
		unlockSlowImpl!true(null);
	}

	void unlockSlowImpl(bool Fair)(WaitParams* wp) shared {
		if (Fair) {
			assert(wp is null, "Cannot unlock condition fairly!");

			// Make sure that the optimizer knows that wp is null
			// when asserts are disabled.
			wp = null;
		}

		auto fastUnlock = wp is null ? 0 : selfEnqueue(wp);

		auto current = word.load(MemoryOrder.Relaxed);
		while (true) {
			assert(current & LockBit, "Lock not held!");

			// If nobody is parked, just unlock.
			if (current == LockBit) {
				if (word.casWeak(current, fastUnlock, MemoryOrder.Release)) {
					return;
				}

				continue;
			}

			// If the queue is locked, just wait.
			if (current & QueueLockBit) {
				sched_yield();
				current = word.load(MemoryOrder.Relaxed);
				continue;
			}

			// We must have another thread waiting. Lock the queue
			// and release the next thread in line.
			if (word.casWeak(current, current | QueueLockBit,
			                 MemoryOrder.Acquire)) {
				break;
			}
		}

		// Make sure we do have the queue lock.
		assert(word.load() & QueueLockBit, "Queue lock not acquired!");

		/**
		 * FIXME: We might end up running through the same conditions
		 *        again and again with that strategy. A better approach
		 *        would be to make sure we dequeu at least one non condition
		 *        thread if there is one, maybe?
		 */
		ThreadData* wakeList;
		if (wp is null) {
			current = dequeueLock(current, wakeList);
		} else {
			current = dequeueCondition(current, wp, wakeList);
		}

		/**
		 * As we update the tail, we also release the queue lock.
		 * The lock itself is kept is the fair case, or unlocked if
		 * fairness is not a concern.
		 */
		word.store(current | Fair, MemoryOrder.Release);
		assert(!Fair || wakeList !is null, "Expected at least one dequeue!");

		// Make sure our bit trickery remains valid.
		static assert((Handoff.Barging + true) == Handoff.Direct);

		// Wake up the blocked threads.
		auto fair = Fair;
		while (wakeList !is null) {
			auto c = wakeList;
			wakeList = c.next;

			c.waitParams.handoff
			 .store(Handoff.Barging + fair, MemoryOrder.Release);
			c.waiter.wakeup();

			fair = false;
		}
	}

	/**
	 * When the mutex is contended, thread queue to get their turn.
	 */
	static size_t selfEnqueue(WaitParams* wp) {
		// Make sure we are setup for handoff.
		wp.handoff.store(Handoff.None, MemoryOrder.Release);

		auto me = &threadData;
		me.waitParams = wp;

		me.next = me;
		me.skip = null;

		return cast(size_t) me;
	}

	static size_t enqueueLock(size_t current, WaitParams* wp) {
		assert(current & LockBit, "Lock not held!");
		assert(wp.isLock(), "Expected a lock!");

		auto tail = cast(ThreadData*) (current & ThreadDataMask);
		return cast(size_t) enqueueLock(tail, wp);
	}

	static ThreadData* prepend(ThreadData* tail, WaitParams* wp) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		// Make sure we are setup for handoff.
		wp.handoff.store(Handoff.None, MemoryOrder.Release);

		auto me = &threadData;
		me.waitParams = wp;

		assert(me !is tail, "Invalid insert!");

		me.next = tail.next;
		tail.next = me;

		me.skip = null;
		me.updateSkip();

		return tail;
	}

	static ThreadData* enqueueAfter(ThreadData* tail, ThreadData* prev,
	                                WaitParams* wp) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		assert(prev !is null, "Invalid prev!");
		assert(prev.skip is null, "Prev cannot have a skip!");

		// Make sure we are setup for handoff.
		wp.handoff.store(Handoff.None, MemoryOrder.Release);

		auto me = &threadData;
		me.waitParams = wp;

		assert(me !is tail && me !is prev, "Invalid insert!");

		me.next = prev.next;
		me.skip = null;

		prev.next = me;
		prev.updateSkip();

		return prev is tail ? me : tail;
	}

	static ThreadData* enqueueLock(ThreadData* tail, WaitParams* wp) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		assert(wp.isLock(), "Expected a lock!");

		// If this is the highest priority item, prepend.
		auto head = tail.next;
		if (head.isCondition()) {
			return prepend(tail, wp);
		}

		return enqueueAfter(tail, head.skipForward(), wp);
	}

	static size_t dequeueLock(size_t current, ref ThreadData* wakeList) {
		assert(current & LockBit, "Lock not held!");

		auto tail = cast(ThreadData*) (current & ThreadDataMask);
		return cast(size_t) dequeueLock(tail, wakeList);
	}

	static ThreadData* dequeueAfter(bool AcceptTail = true)(ThreadData* tail,
	                                                        ThreadData* prev) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		assert(prev !is null, "Invalid prev!");
		assert(prev.skip is null, "Prev cannot have a skip!");

		auto n = prev.next;
		prev.next = n.next;

		if (AcceptTail && n is tail) {
			// We either have an empty list or removed the tail.
			return prev is n ? null : prev;
		}

		assert(n !is tail, "Cannot dequeue tail!");

		// The list is not empty.
		if (prev !is tail) {
			prev.updateSkip();
		}

		return tail;
	}

	static ThreadData* dequeueLock(ThreadData* tail, ref ThreadData* wakeList) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		auto p = tail;
		auto c = tail.next;

		tail = dequeueAfter(tail, p);

		c.next = null;
		wakeList = c;
		return tail;
	}

	static size_t dequeueCondition(size_t current, WaitParams* wp,
	                               ref ThreadData* wakeList) {
		assert(current & LockBit, "Lock not held!");

		auto tail = cast(ThreadData*) (current & ThreadDataMask);
		return cast(size_t) dequeueCondition(tail, wp, wakeList);
	}

	static ThreadData* dequeueCondition(ThreadData* tail, WaitParams* wp,
	                                    ref ThreadData* wakeList) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		tail = enqueueAfter(tail, tail, wp);

		auto p = tail;
		auto c = tail.next;

		if (c.isEquivalentTo(wp)) {
			p = c.skipForward();
			if (p is tail) {
				wakeList = null;
				return tail;
			}

			c = p.next;
		}

		assert(!c.isEquivalentTo(wp), "Invalid list!");
		tail = dequeueAfter!false(tail, p);

		c.next = null;
		wakeList = c;
		return tail;
	}
}

unittest locking {
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

	import core.stdc.pthread;
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

unittest fairness {
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

	import core.stdc.pthread;
	pthread_t[ThreadCount] ts;
	foreach (i; 0 .. ThreadCount) {
		ts[i] = run(i);
	}

	mutex.unlock();

	import core.stdc.unistd;
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

unittest condition {
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

	enum ThreadCount = 1024;

	shared Mutex mutex;
	uint next = -1;

	auto run(uint i) {
		void* fun() {
			bool check0() {
				return next == i;
			}

			bool check1() {
				return next == i;
			}

			mutex.lock();

			mutex.waitFor(check0);
			next++;

			mutex.waitFor(check1);
			next--;

			mutex.unlock();

			return null;
		}

		return runThread(fun);
	}

	// Start the threads.
	mutex.lock();

	import core.stdc.pthread;
	pthread_t[ThreadCount] ts;
	foreach (i; 0 .. ThreadCount) {
		ts[i] = run(i);
	}

	bool reachedReversePoint() {
		return next == ThreadCount;
	}

	bool reachedStartPoint() {
		return next == -1;
	}

	// Hand things over to the threads.
	next = 0;
	mutex.waitFor(reachedReversePoint);

	next--;
	mutex.waitFor(reachedStartPoint);

	mutex.unlock();

	// Now join them all and check next.
	foreach (i; 0 .. ThreadCount) {
		void* ret;
		pthread_join(ts[i], &ret);
	}

	mutex.lock();
	assert(next == -1);
	mutex.unlock();
}
