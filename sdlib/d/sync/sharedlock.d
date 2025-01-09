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
	bool noWriteLock() {
		return count < Exclusive;
	}

	void sharedLockImpl() {
		assert(mutex.isHeld());
		mutex.waitFor(noWriteLock);
		++count;
	}

	bool hasExclusiveLock() {
		return count == Exclusive;
	}

	void exclusiveLockImpl() {
		assert(mutex.isHeld());
		// Wait for no other exclusive lock.
		mutex.waitFor(noWriteLock);
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
		assert(lock.count == 51);

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
	// Test using the exclusive lock. First, check that the state is as
	// expected, then test trying to lock exclusively while holding a
	// shared lock, and finally test exclusive locks as a mutex between 2
	// threads.
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

	lock.sharedLock();
	assert(lock.count == 1);

	// Attempt to exclusive lock while the shared lock is held.
	import core.stdc.pthread;
	import d.sync.atomic;
	shared Atomic!uint state;

	void* takeExclusiveLock() {
		state.fetchAdd(1);
		lock.exclusiveLock();
		state.fetchAdd(1);
		return cast(void*) cast(size_t) lock.count;
	}

	void* takeSharedLock() {
		lock.sharedLock();
		state.fetchAdd(1);
		return null;
	}

	auto t1 = runThread(takeExclusiveLock);

	{
		bool triedExclusiveLock() {
			return lock.count >= SharedLock.Exclusive;
		}

		lock.mutex.lock();
		scope(exit) lock.mutex.unlock();

		lock.mutex.waitFor(triedExclusiveLock);
		assert(lock.count == SharedLock.Exclusive + 1);
		assert(state.load() == 1);
	}

	auto t2 = runThread(takeSharedLock);

	// Give t2 some time to try locking, sleep 0.5s
	import core.stdc.unistd;
	usleep(1000 * 500);
	assert(lock.count == SharedLock.Exclusive + 1);
	assert(state.load() == 1);

	lock.sharedUnlock();
	assert(lock.count == SharedLock.Exclusive);

	void* ret;
	pthread_join(t1, &ret);

	assert(lock.mutex.isHeld());
	assert(cast(size_t) ret == SharedLock.Exclusive);
	assert(state.load() == 2);

	lock.exclusiveUnlock();
	pthread_join(t2, &ret);
	assert(lock.count == 1);
	assert(state.load() == 3);

	lock.sharedUnlock();
	assert(lock.count == 0);

	void* run1() {
		assert(state.load() == 0);

		lock.exclusiveLock();
		assert(lock.count == SharedLock.Exclusive, "Invalid lock state!");
		assert(lock.mutex.isHeld(), "Mutex not held while exclusively locked!");
		state.store(1);
		lock.exclusiveUnlock();

		while (state.load() != 2) {
			import sys.posix.sched;
			sched_yield();
		}

		return null;
	}

	void* run2() {
		while (state.load() != 1) {
			import sys.posix.sched;
			sched_yield();
		}

		assert(state.load() == 1);

		lock.exclusiveLock();
		assert(lock.count == SharedLock.Exclusive, "Invalid lock state!");
		assert(lock.mutex.isHeld(), "Mutex not held while exclusively locked!");
		state.store(2);
		lock.exclusiveUnlock();

		return null;
	}

	state.store(0);
	auto t3 = runThread(run1);
	auto t4 = runThread(run2);

	pthread_join(t3, &ret);
	pthread_join(t4, &ret);

	assert(!lock.mutex.isHeld(), "Mutex not held!");
	assert(lock.count == 0, "Invalid lock state!");
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

	enum MaxExclusive = 5;
	enum MaxShared = 50;

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
