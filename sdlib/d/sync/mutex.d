module d.sync.mutex;

import sdc.intrinsics;

import core.stdc.sched;

struct Mutex {
private:
	import d.sync.atomic;
	Atomic!size_t word;

	enum size_t LockBit = 0x01;
	enum size_t QueueLockBit = 0x02;
	enum size_t HasWakerBit = 0x04;
	enum size_t AllFlags = LockBit | QueueLockBit | HasWakerBit;
	enum size_t ThreadDataMask = ~AllFlags;

public:
	void lock()() shared {
		// No operation done after the lock is taken can be reordered before.
		size_t current = 0;
		if (likely(word.casWeak(current, LockBit, MemoryOrder.Acquire))) {
			return;
		}

		lockSlow(current);
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

	void unlock()() shared {
		// No operation done before the lock is freed can be reordered after.
		size_t current = LockBit;
		if (likely(word.casWeak(current, 0, MemoryOrder.Release))) {
			return;
		}

		unlockSlowUnfair(current);
	}

	void unlockFairly()() shared {
		// No operation done before the lock is freed can be reordered after.
		size_t current = LockBit;
		if (likely(word.casWeak(current, 0, MemoryOrder.Release))) {
			return;
		}

		unlockSlowFair(current);
	}

	bool waitFor()(bool delegate() condition) shared {
		assert((&this).isHeld(), "Mutex not held!");

		WaitParams wp;
		wp.condition = condition;

		while (true) {
			if (condition()) {
				return true;
			}

			// FIXME: In case of timeout, we want to return false.
			//        At the moment, timeouts are not supported.
			unlockAndWait(&wp);
		}
	}

	bool notify()() shared {
		auto current = word.load(MemoryOrder.Relaxed);

		while (true) {
			// The thread is not contended, we are done.
			if (current == 0) {
				return false;
			}

			// We have a designated waker, let it do the work.
			if (current & HasWakerBit) {
				return false;
			}

			/**
			 * FIXME: notify() is allowed to return while LockBit is set
			 *        without leaving a note for the holder. That loses
			 *        wakeups in two cases:
			 *
			 * 1. The holder already walked the queue, found nobody runnable,
			 *    and is about to drop the lock. We made a waiter runnable
			 *    and called notify(); the walk will not run again.
			 *
			 * 2. A waitFor() thread sampled its condition as false and is
			 *    parking. We made that condition true and called notify();
			 *    the thread still parks.
			 *
			 * Fix: when notify() sees LockBit, set a notified flag in
			 * the word. Unlock / park must observe that flag after
			 * the walk (or after the condition sample) and either rescan
			 * or re-evaluate before blocking.
			 *
			 * That makes both notify and unlock heavier. A designated-waker
			 * bit pays for it: the thread we just woke is marked in the word
			 * and in its WaitParams. Later notify() can return as that thread
			 * will walk. A barging unlock can skip dequeue for the same reason.
			 */
			if (current & LockBit) {
				return false;
			}

			// If we do not have a waiter, we are done.
			if (!(current & ThreadDataMask)) {
				return false;
			}

			assert(!(current & QueueLockBit),
			       "Queue lock held while unlocked!");
			if (word.casWeak(current, current | LockBit, MemoryOrder.Acquire)) {
				unlockSlowUnfair(current | LockBit);
				return true;
			}
		}
	}

	/**
	 * /!\: This will reset the state of the mutex.
	 *      If it was locked, it is now unlocked.
	 *      If there were thread waiting for it, they are probably
	 *      lost forever.
	 *      This method is almost certainly not what you want to use.
	 */
	void __clear()() shared {
		word.store(0);
	}

private:
	enum Handoff {
		None,
		Direct,
		Barging,
		Waker,
	}

	/**
	 * When the lock is contended, we create a linked list
	 * representing the threads waiting on the lock.
	 *
	 * The linked list loops around (the tail points to the head)
	 * and the mutex itself points to the tail, such as
	 * tail.next == head.
	 */
	struct ThreadData {
		// Covered by the queue lock.
		WaitParams* waitParams;

		ThreadData* next;
		ThreadData* skip;

		import d.sync.waiter;
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

				// We update the skip list as we travel it so we can
				// recompute it faster next time.
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

	void lockSlow(size_t current) shared {
		WaitParams wp;
		lockSlow(current, &wp, false);
	}

	void lockSlow(size_t current, WaitParams* wp, bool waker) shared {
		// Trusting WTF::WordLock on that one...
		enum SpinLimit = 40;
		uint spinCount = 0;

		// A waker must clear the waker bit, but other thread must preserve it.
		enum size_t BargingMask = HasWakerBit;
		enum size_t WakerMask = 0;

		auto mask = waker ? WakerMask : BargingMask;

		while (true) {
			auto flags = (current & mask) | LockBit;

			// If the lock if free, we try to barge in.
			if (!(current & LockBit)) {
				assert(!(current & QueueLockBit),
				       "Queue lock held while unlocked!");

				auto desired = current & ThreadDataMask;
				if (word.casWeak(current, desired | flags,
				                 MemoryOrder.Acquire)) {
					// We got the lock, VICTORY !
					return;
				}

				continue;
			}

			assert(current & LockBit, "Lock not held!");

			// If nobody's parked...
			if (!(current & ThreadDataMask)) {
				// First, we spin.
				if (spinCount < SpinLimit) {
					spinCount++;
					sched_yield();
					current = word.load(MemoryOrder.Relaxed);
					continue;
				}

				// Then we try to park oursleves atomically.
				if (word.casWeak(current, selfEnqueue(wp) | flags,
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
				current = word.load(MemoryOrder.Relaxed);
				continue;
			}

			// Make sure we do have the queue lock.
			assert(word.load() & QueueLockBit, "Queue lock not acquired!");

			// Now we store the updated head. Note that this will release the
			// queue lock too, but it's okay, by now we are in the queue.
			word.store(enqueue(current, wp) | flags, MemoryOrder.Release);

		Handoff:
			auto handoff = waitForHandoff();
			if (handoff == Handoff.Direct) {
				assert((&this).isHeld(), "Lock not held!");
				return;
			}

			mask = (handoff == Handoff.Waker) ? WakerMask : BargingMask;
			current = word.load(MemoryOrder.Relaxed);
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

		// FIXME: out contract.
		assert(
			handoff == Handoff.Direct || handoff == Handoff.Barging
				|| handoff == Handoff.Waker,
			"Invalid handoff state!"
		);
		return handoff;
	}

	void unlockAndWait(WaitParams* wp) shared {
		auto current = word.load(MemoryOrder.Relaxed);
		assert(current & LockBit, "Lock not held!");

		unlockSlowCondition(current, wp);

		auto handoff = waitForHandoff();
		if (handoff != Handoff.Direct) {
			// We assume that either we are the waker, or someone else is.
			lockSlow(HasWakerBit, wp, handoff == Handoff.Waker);
		}

		assert((&this).isHeld(), "Lock not held!");
	}

	enum UnlockKind {
		Fair,
		Unfair,
		Condition,
	}

	void unlockSlowFair(size_t current) shared {
		unlockSlowImpl!(UnlockKind.Fair)(current, null);
	}

	void unlockSlowUnfair(size_t current) shared {
		unlockSlowImpl!(UnlockKind.Unfair)(current, null);
	}

	void unlockSlowCondition(size_t current, WaitParams* wp) shared {
		unlockSlowImpl!(UnlockKind.Condition)(current, wp);
	}

	void unlockSlowImpl(/* UnlockKind */ int Kind)(size_t current,
	                                               WaitParams* wp) shared {
		enum Fair = Kind == UnlockKind.Fair;
		enum Condition = Kind == UnlockKind.Condition;
		if (Condition) {
			assert(wp !is null && wp.isCondition(), "Expected a condition!");
		} else {
			assert(wp is null, "Cannot unlock condition fairly!");
		}

		while (true) {
			assert(current & LockBit, "Lock not held!");

			enum FastUnlockMask = ThreadDataMask | QueueLockBit;

			// If nobody is parked, just unlock.
			if (!(current & FastUnlockMask)) {
				auto desired = Condition ? selfEnqueue(wp) : 0;
				desired |= current & HasWakerBit;

				if (word.casWeak(current, desired, MemoryOrder.Release)) {
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

			// We already have a designated waker, just unlock.
			// Conditions still need to add themselves to the list.
			if (!Condition && (current & HasWakerBit)) {
				if (word.casWeak(current, current & ~LockBit,
				                 MemoryOrder.Release)) {
					return;
				}

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

		auto flags = current & HasWakerBit;

		// If we have a condition, add it to the list.
		if (Condition) {
			current = enqueue(current, wp);

			// We we have a waker, exit ASAP.
			if (flags & HasWakerBit) {
				word.store(current | flags, MemoryOrder.Release);
				return;
			}
		}

		/**
		 *  The only way we could get the queue lock when there is a
		 * designated waker is to enqueue ourselves, which is done by now.
		 */
		assert(!(flags & HasWakerBit),
		       "Reached dequeing code while not the designated waker!");

		/**
		 * Wake one waiter that can run. If every condition is false and
		 * nobody is waiting for the lock itself, wake nobody.
		 */
		ThreadData* wakeList;
		current = dequeue(current, wakeList, wp);

		// We we don't have anyone to wake, then we are done.
		if (wakeList is null) {
			word.store(current, MemoryOrder.Release);
			return;
		}

		/**
		 * As we update the tail, we also release the queue lock.
		 * Fair handoff keeps LockBit only when there is a winner.
		 */
		current |= Fair ? LockBit : HasWakerBit;
		word.store(current, MemoryOrder.Release);

		// First, do an ownership transfer if one is warranted.
		auto c = wakeList;
		wakeList = c.next;

		auto handoff = Fair ? Handoff.Direct : Handoff.Waker;
		c.waitParams.handoff.store(handoff, MemoryOrder.Release);
		c.waiter.wakeup();

		// If there are more threads to wake up, do so.
		while (wakeList !is null) {
			auto c = wakeList;
			wakeList = c.next;

			c.waitParams.handoff.store(Handoff.Barging, MemoryOrder.Release);
			c.waiter.wakeup();
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

	static ThreadData* enqueue(ThreadData* tail, WaitParams* wp) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		// We just enqueue condition at the end of the queue.
		if (wp.isCondition()) {
			return enqueueAfter(tail, tail, wp);
		}

		// If this is the highest priority item, prepend.
		auto head = tail.next;
		if (head.isCondition()) {
			return prepend(tail, wp);
		}

		return enqueueAfter(tail, head.skipForward(), wp);
	}

	static size_t enqueue(size_t current, WaitParams* wp) {
		assert(current & LockBit, "Lock not held!");

		auto tail = cast(ThreadData*) (current & ThreadDataMask);
		return cast(size_t) enqueue(tail, wp);
	}

	static ThreadData* dequeueAfter(ThreadData* tail, ThreadData* prev) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");

		assert(prev !is null, "Invalid prev!");
		assert(prev.skip is null, "Prev cannot have a skip!");

		auto n = prev.next;
		prev.next = n.next;

		if (n is tail) {
			// We either have an empty list or removed the tail.
			return prev is n ? null : prev;
		}

		// The list is not empty.
		if (prev !is tail) {
			prev.updateSkip();
		}

		return tail;
	}

	static ThreadData* dequeue(ThreadData* tail, ref ThreadData* wakeList,
	                           WaitParams* wp) {
		assert(tail !is null, "Failed to short circuit on empty queue!");
		assert(tail.skip is null, "Tail cannot have a skip!");
		assert(wakeList is null, "wakeList wasn't empty!");
		assert(wp is null || wp.isCondition(),
		       "wp must be null or a condition!");

		auto p = tail;

		while (true) {
			auto c = p.next;

			if (c.isLock() || ((wp is null || !c.isEquivalentTo(wp))
				    && c.waitParams.condition())) {
				tail = dequeueAfter(tail, p);
				c.next = null;
				wakeList = c;
				return tail;
			}

			p = c.skipForward();
			if (p is tail) {
				return tail;
			}
		}
	}

	static size_t dequeue(size_t current, ref ThreadData* wakeList,
	                      WaitParams* wp = null) {
		assert(wp is null || wp.isCondition(),
		       "wp must be null or a condition!");

		auto tail = cast(ThreadData*) (current & ThreadDataMask);
		return cast(size_t) dequeue(tail, wakeList, wp);
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

	import d.sync.atomic;
	shared Atomic!uint count;
	bool latch = false;

	auto run(uint i) {
		void* fun() {
			bool check0() {
				return next == i;
			}

			bool check1() {
				return next == i;
			}

			mutex.lock();
			scope(exit) mutex.unlock();

			mutex.waitFor(check0);
			next++;

			mutex.waitFor(check1);
			next--;

			bool latchReleased() {
				count.fetchAdd(1);
				return latch;
			}

			mutex.waitFor(latchReleased);

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

	// Handshake done, lock held, every worker is in waitFor(parked)
	// with a false, non-equivalent predicate. Drop the lock: the old
	// wake-next policy rotates; evaluating predicates leaves count still.
	auto snapshot = count.load();
	foreach (_; 0 .. 8) {
		sched_yield();
		assert(count.load() == snapshot, "waitFor bucket brigade");
	}

	mutex.lock();
	latch = true;
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

unittest notify {
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

	enum uint ThreadCount = 8;

	shared Mutex mutex;

	// Notify while locked is a noop.
	mutex.lock();
	assert(!mutex.notify());

	// Notify with no waiters is also a noop.
	mutex.unlock();
	assert(!mutex.notify());

	import d.sync.atomic;
	shared Atomic!uint entered;
	shared Atomic!uint passed;
	shared Atomic!uint[ThreadCount] ready;

	auto run(uint i) {
		void* fun() {
			bool canProceed() {
				return ready[i].load() != 0;
			}

			mutex.lock();
			entered.fetchAdd(1);
			mutex.waitFor(canProceed);
			passed.fetchAdd(1);
			mutex.unlock();
			return null;
		}

		return runThread(fun);
	}

	import core.stdc.pthread;
	pthread_t[ThreadCount] ts;
	foreach (i; 0 .. ThreadCount) {
		ts[i] = run(i);
	}

	bool allEntered() {
		return entered.load() == ThreadCount;
	}

	mutex.lock();
	mutex.waitFor(allEntered);
	mutex.unlock();

	// Notify while threads are waiting returns true,
	// even in the case none are woken up.
	assert(passed.load() == 0);
	assert(mutex.notify());
	assert(passed.load() == 0);

	void* ret;
	foreach (i; 0 .. ThreadCount) {
		ready[i].store(1);
		assert(mutex.notify());

		pthread_join(ts[i], &ret);
		assert(passed.load() == i + 1);
	}

	// Nobody's waiting anymore, notify is a noop again.
	assert(!mutex.notify());
}
