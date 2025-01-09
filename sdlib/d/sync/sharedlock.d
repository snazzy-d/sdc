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
	assert(lock.count == 0);
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
		scope(exit) lock.sharedUnlock();
		numLocked.fetchAdd(1);
		mutex.lock();
		scope(exit) mutex.unlock();
		bool shouldExit() {
			return exitThread;
		}

		mutex.waitFor(shouldExit);
		return null;
	}

	import core.stdc.pthread;
	pthread_t[50] tids;
	foreach (i; 0 .. tids.length) {
		tids[i] = runThread(run);
	}

	{
		bool allThreadsReady() {
			return numLocked.load() == tids.length;
		}

		mutex.lock();
		scope(exit) mutex.unlock();
		mutex.waitFor(allThreadsReady);
	}

	assert(lock.count == 51);
	{
		mutex.lock();
		scope(exit) mutex.unlock();
		exitThread = true;
	}

	void* ret;
	foreach (i; 0 .. tids.length) {
		pthread_join(tids[i], &ret);
	}

	assert(lock.count == 1);
	lock.sharedUnlock();
	assert(lock.count == 0);
}

unittest exclusiveLock {
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

	auto writer = runThread(takeExclusiveLock);
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

	lock.sharedUnlock();
	assert(lock.count == SharedLock.Exclusive);
	void* ret;
	pthread_join(writer, &ret);
	assert(cast(size_t) ret == SharedLock.Exclusive);
	assert(state.load() == 2);
	lock.exclusiveUnlock();
	assert(lock.count == 0);
}

unittest threadStressTest {
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
	shared Mutex mutex;
	bool runTest;

	bool shouldRunTest() {
		return runTest;
	}

	enum MaxExclusive = 5;
	enum MaxShared = 50;

	void* runExclusive() {
		mutex.lock();
		mutex.waitFor(shouldRunTest);
		mutex.unlock();

		foreach (i; 0 .. 10000) {
			lock.exclusiveLock();
			scope(exit) lock.exclusiveUnlock();
			auto ne = numExclusiveLocks.fetchAdd(1);
			auto ns = numSharedLocks.load();
			assert(ne == 0);
			assert(ns == 0);
			import sys.posix.sched;
			sched_yield();
			ne = numExclusiveLocks.fetchSub(1);
			assert(ne == 1);
		}

		return null;
	}

	void* runShared() {
		mutex.lock();
		mutex.waitFor(shouldRunTest);
		mutex.unlock();

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

	import core.stdc.pthread;
	pthread_t[MaxExclusive] exclusives;
	pthread_t[MaxShared] sharers;

	foreach (i; 0 .. exclusives.length) {
		exclusives[i] = runThread(runExclusive);
	}

	foreach (i; 0 .. sharers.length) {
		sharers[i] = runThread(runShared);
	}

	mutex.lock();
	runTest = true;
	mutex.unlock();

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
