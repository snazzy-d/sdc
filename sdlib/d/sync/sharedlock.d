module d.sync.sharedlock;

import d.sync.mutex;

/**
 * SharedLock allows either one exclusive holder, or N shared holders. While any thread
 * has the lock shared, one looking to exclusively lock must wait. When
 * exclusive lock is requested, no new requests to lock will be granted, but
 * existing holders can unlock.
 */
struct SharedLock {
private:
	shared Mutex mutex;
	size_t count;
	enum size_t Exclusive = 1 << (size_t.sizeof * 8 - 1);

public:
	/**
	 * Lock unexclusively.
	 *
	 * Can be locked by any number of threads unexclusively. An exclusive
	 * lock cannot be obtained until all unexclusive locks are released.
	 */
	void sharedLock() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(SharedLock*) &this).sharedLockImpl();
	}

	void sharedUnlock() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(SharedLock*) &this).exclusiveUnlockImpl();
	}

	/**
	 * Lock exclusively.
	 *
	 * Upon return, no other threads can hold this locked.
	 */
	void exclusiveLock() shared {
		mutex.lock();

		(cast(SharedLock*) &this).exclusiveLockImpl();
	}

	void exclusiveUnlock() shared {
		assert(mutex.isHeld());
		scope(exit) mutex.unlock();

		(cast(SharedLock*) &this).unlockWriteImpl();
	}

private:
	bool noExclusiveLock() {
		return count < Exclusive;
	}

	void sharedLockImpl() {
		assert(mutex.isHeld());
		mutex.waitFor(noExclusiveLock);
		++count;
	}

	bool hasExclusiveLock() {
		return count == Exclusive;
	}

	void exclusiveLockImpl() {
		assert(mutex.isHeld());
		// Wait for no other exclusive lock.
		mutex.waitFor(noExclusiveLock);
		count += Exclusive;
		mutex.waitFor(hasExclusiveLock);
	}

	void exclusiveUnlockImpl() {
		assert(mutex.isHeld());
		assert((count & ~Exclusive) > 0);
		--count;
	}

	void unlockWriteImpl() {
		assert(mutex.isHeld());
		assert(count == Exclusive);
		count = 0;
	}
}

unittest sharedLocks {
	// Simple testing of shared locks, then test multiple threads acquiring
	// the lock.
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

	shared SharedLock lock;

	lock.sharedLock();
	assert(lock.count == 1);
	assert(!lock.mutex.isHeld());

	lock.sharedLock();
	assert(lock.count == 2);

	lock.sharedUnlock();
	assert(lock.count == 1);

	import d.sync.atomic;
	shared Mutex mutex;
	shared Atomic!uint numLocked;
	bool exitThread;

	void* run() {
		lock.sharedLock();

		numLocked.fetchAdd(1);

		mutex.lock();
		scope(exit) mutex.unlock();

		bool shouldExit() {
			return exitThread;
		}

		mutex.waitFor(shouldExit);
		lock.sharedUnlock();
		numLocked.fetchSub(1);
		return null;
	}

	import core.stdc.pthread;
	pthread_t[50] tids;
	foreach (i; 0 .. tids.length) {
		tids[i] = runThread(run);
	}

	{
		mutex.lock();
		scope(exit) mutex.unlock();

		bool allThreadsReady() {
			return numLocked.load() == tids.length;
		}

		mutex.waitFor(allThreadsReady);
		assert(lock.count == tids.length + 1);

		exitThread = true;

		bool allThreadsDone() {
			return numLocked.load() == 0;
		}

		mutex.waitFor(allThreadsDone);
		assert(lock.count == 1);
	}

	void* ret;
	foreach (i; 0 .. tids.length) {
		pthread_join(tids[i], &ret);
	}

	lock.sharedUnlock();
	assert(lock.count == 0);
}

unittest exclusiveLock {
	// Test using the exclusive lock. Ensure only one thread can hold the
	// lock at any given time.
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

	shared SharedLock lock;

	lock.exclusiveLock();
	assert(lock.count == SharedLock.Exclusive);

	lock.exclusiveUnlock();
	assert(lock.count == 0);

	static struct State {
		uint state;
		shared Mutex mutex;

		void store(uint s) {
			mutex.lock();
			scope(exit) mutex.unlock();

			state = s;
		}

		uint load() {
			mutex.lock();
			scope(exit) mutex.unlock();

			return state;
		}

		void waitFor(uint value) {
			auto ths = &this;
			bool matches() {
				return ths.state == value;
			}

			mutex.lock();
			scope(exit) mutex.unlock();
			mutex.waitFor(matches);
		}
	}

	State state;

	void* run1() {
		assert(state.load() == 0);

		lock.exclusiveLock();
		assert(lock.count == SharedLock.Exclusive, "Invalid lock state!");
		assert(lock.mutex.isHeld(), "Mutex not held while exclusively locked!");
		state.store(1);
		lock.exclusiveUnlock();

		state.waitFor(2);

		return null;
	}

	void* run2() {
		state.waitFor(1);

		assert(state.load() == 1);

		lock.exclusiveLock();
		assert(lock.count == SharedLock.Exclusive, "Invalid lock state!");
		assert(lock.mutex.isHeld(), "Mutex not held while exclusively locked!");
		state.store(2);
		lock.exclusiveUnlock();

		return null;
	}

	auto t1 = runThread(run1);
	auto t2 = runThread(run2);

	import core.stdc.pthread;
	void* ret;
	pthread_join(t1, &ret);
	pthread_join(t2, &ret);

	assert(!lock.mutex.isHeld(), "Mutex is held!");
	assert(lock.count == 0, "Invalid lock state!");
}

unittest exclusiveAndSharedLock {
	/**
	 * Test the following scenarios:
	 * 1. When a shared lock is held, exclusively locking waits.
	 * 2. When a shared lock is held, and exclusive lock is sought, further
	 *    shared locks should wait.
	 * 3. When all shared locks are released, the exclusive lock is taken.
	 * 4. When the exclusive lock is released, shared locks can again be taken.
	 *
	 * To accomplish this, we will start one exclusive thread and several
	 * sharing threads. We will issue commands for each action, and then
	 * wait for the desired state, then we measure the lock state and
	 * ensure everything is correct.
	 */
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

	shared SharedLock lock;

	enum SharerThreads = 5;

	static struct ExclusiveState {
		shared Mutex mutex;
		uint state;

		uint load() {
			mutex.lock();
			scope(exit) mutex.unlock();
			return state;
		}

		void store(uint newval) {
			mutex.lock();
			scope(exit) mutex.unlock();
			state = newval;
		}

		bool cmdReady() {
			return (state & 1) == 1;
		}

		uint waitForCmd() {
			mutex.lock();
			scope(exit) mutex.unlock();

			mutex.waitFor(cmdReady);
			return state;
		}

		bool responseReady() {
			return (state & 1) == 0;
		}

		uint waitForResponse() {
			mutex.lock();
			scope(exit) mutex.unlock();

			mutex.waitFor(responseReady);
			return state;
		}
	}

	ExclusiveState exclusiveState;

	void* exclusiveLocker() {
		while (true) {
			auto s = exclusiveState.waitForCmd();

			scope(exit) exclusiveState.store(s + 1);

			switch (s) {
				case 1: // Lock
					lock.exclusiveLock();
					break;
				case 3: // Unlock
					lock.exclusiveUnlock();
					break;
				default: // Exit
					return null;
			}
		}
	}

	static struct SharedState {
		shared Mutex mutex;
		uint _locked;
		uint _attempted;
		uint _desired;
		uint _lockerId;
		shared(SharedLock)* slock;

		this(shared(SharedLock)* slock) {
			this.slock = slock;
		}

		uint inc(ref uint var) {
			mutex.lock();
			scope(exit) mutex.unlock();
			return var++;
		}

		uint dec(ref uint var) {
			mutex.lock();
			scope(exit) mutex.unlock();
			return var--;
		}

		uint load(ref uint var) {
			mutex.lock();
			scope(exit) mutex.unlock();
			return var;
		}

		void store(ref uint var, uint newval) {
			mutex.lock();
			scope(exit) mutex.unlock();
			var = newval;
		}

		uint nextId() {
			return inc(_lockerId);
		}

		void lock() {
			inc(_attempted);
			slock.sharedLock();
			dec(_attempted);
			inc(_locked);
		}

		void unlock() {
			slock.sharedUnlock();
			dec(_locked);
		}

		void waitForState(uint locked, uint attempted) {
			auto ths = &this;
			bool stateMatched() {
				return ths._locked == locked && ths._attempted == attempted;
			}

			mutex.lock();
			mutex.waitFor(stateMatched);
			mutex.unlock();

			// Sleep a tiny bit (10ms) to ensure a steady state
			import core.stdc.unistd;
			usleep(10 * 1000);

			assert(load(_locked) == locked,
			       "Unexpected change of shared locks!");
			assert(load(_attempted) == attempted,
			       "Unexpected change of shared attempts!");
		}

		void waitForDesiredChanged(uint current) {
			auto ths = &this;
			bool desiredChanged() {
				return ths._desired != current;
			}

			mutex.lock();
			scope(exit) mutex.unlock();

			mutex.waitFor(desiredChanged);
		}

		uint desired() {
			return load(_desired);
		}

		void setDesired(uint count) {
			store(_desired, count);
		}
	}

	auto sharedState = SharedState(&lock);

	void* sharedLocker() {
		uint id = sharedState.nextId();
		bool lockHeld = false;
		while (true) {
			uint cmd = sharedState.desired();
			if (cmd == uint.max) {
				return null;
			}

			if (cmd > id && !lockHeld) {
				sharedState.lock();
				lockHeld = true;
			} else if (cmd <= id && lockHeld) {
				sharedState.unlock();
				lockHeld = false;
			} else {
				sharedState.waitForDesiredChanged(cmd);
			}
		}
	}

	import core.stdc.pthread;
	pthread_t[SharerThreads + 1] tids;
	tids[0] = runThread(exclusiveLocker);
	foreach (i; 1 .. tids.length) {
		tids[i] = runThread(sharedLocker);
	}

	// 1. When a shared lock is held, exclusively locking waits.
	sharedState.setDesired(2);

	sharedState.waitForState(2, 0);
	assert(lock.count == 2, "Expected count not correct!");
	assert(!lock.mutex.isHeld(), "Mutex is held!");

	exclusiveState.store(1);
	bool exclusiveAttempted() {
		return lock.count >= SharedLock.Exclusive;
	}

	lock.mutex.lock();
	lock.mutex.waitFor(exclusiveAttempted);
	lock.mutex.unlock();

	assert(lock.count == SharedLock.Exclusive + 2);
	assert(!lock.mutex.isHeld());
	assert(exclusiveState.load() == 1);
	sharedState.waitForState(2, 0);

	// 2. When a shared lock is held, and exclusive lock is sought, further
	//    shared locks should wait.
	sharedState.setDesired(SharerThreads);

	sharedState.waitForState(2, SharerThreads - 2);
	assert(lock.count == SharedLock.Exclusive + 2);
	// Lock here, to make sure the lock isn't held by the exclusive thread.
	lock.mutex.lock();
	assert(exclusiveState.load() == 1);
	lock.mutex.unlock();

	// 3. When all shared locks are released, the exclusive lock is taken.
	sharedState.setDesired(0);
	auto response = exclusiveState.waitForResponse();

	sharedState.waitForState(0, SharerThreads - 2);
	assert(response == 2);
	assert(lock.count == SharedLock.Exclusive);
	assert(lock.mutex.isHeld());

	// 4. When the exclusive lock is released, shared locks can again be taken.
	sharedState.setDesired(SharerThreads);

	sharedState.waitForState(0, SharerThreads);
	assert(lock.count == SharedLock.Exclusive);
	assert(lock.mutex.isHeld());
	assert(exclusiveState.load() == 2);

	// Unlock the exclusive lock.
	exclusiveState.store(3);
	response = exclusiveState.waitForResponse();

	sharedState.waitForState(SharerThreads, 0);
	assert(response == 4);
	assert(lock.count == SharerThreads);
	assert(!lock.mutex.isHeld());

	sharedState.setDesired(0);
	sharedState.waitForState(0, 0);

	// Cleanup.
	sharedState.setDesired(uint.max);
	exclusiveState.store(uint.max);
	foreach (i; 0 .. tids.length) {
		void* ret;
		pthread_join(tids[i], &ret);
	}

	assert(lock.count == 0, "Invalid lock state!");
	assert(!lock.mutex.isHeld(), "Lock mutex is held!");
}

unittest threadStressTest {
	// Stress the lock by creating many threads that try both exclusive and
	// shared locking.
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
	shared SharedLock lock;
	shared Atomic!uint numSharedLocks;
	shared Atomic!uint numExclusiveLocks;

	enum MaxExclusive = 20;
	enum MaxShared = 200;

	void* runExclusive() {
		foreach (i; 0 .. 10000) {
			lock.exclusiveLock();
			scope(exit) lock.exclusiveUnlock();

			auto ne = numExclusiveLocks.fetchAdd(1);
			auto ns = numSharedLocks.load();

			assert(ne == 0);
			assert(ns == 0);

			ne = numExclusiveLocks.fetchSub(1);

			assert(ne == 1);
		}

		return null;
	}

	void* runShared() {
		size_t highWater = 0;
		foreach (i; 0 .. 10000) {
			lock.sharedLock();
			scope(exit) lock.sharedUnlock();

			auto ne = numExclusiveLocks.load();
			auto ns = numSharedLocks.fetchAdd(1);

			assert(ne == 0);
			assert(ns >= 0 && ns < MaxShared);

			import sys.posix.sched;
			sched_yield();
			ns = numSharedLocks.fetchSub(1);

			assert(ns > 0 && ns <= MaxShared);

			if (ns > highWater) {
				highWater = ns;
			}
		}

		return cast(void*) highWater;
	}

	lock.exclusiveLock(); // To sync all thread starts.

	import core.stdc.pthread;
	pthread_t[MaxExclusive] exclusives;
	pthread_t[MaxShared] sharers;

	foreach (i; 0 .. exclusives.length) {
		exclusives[i] = runThread(runExclusive);
	}

	foreach (i; 0 .. sharers.length) {
		sharers[i] = runThread(runShared);
	}

	lock.exclusiveUnlock(); // Release all the threads.

	foreach (i; 0 .. exclusives.length) {
		void* ret;
		pthread_join(exclusives[i], &ret);
	}

	size_t highWater;
	foreach (i; 0 .. sharers.length) {
		size_t ret;
		pthread_join(sharers[i], cast(void**) &ret);
		if (ret > highWater) {
			highWater = ret;
		}
	}

	import core.stdc.stdio;
	printf("simultaneous sharers highWater = %lld\n", highWater);
}
