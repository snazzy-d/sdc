module d.sync.rwlock;

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
	enum size_t Exclusive = 1 << 31;

public:
	/**
	 * Lock for reading.
	 *
	 * Can be locked for reading by any number of readers. No writers can
	 * acquire the lock until all readers have unlocked.
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

unittest rwlock {
	import core.stdc.pthread;
	static struct State {
		shared SharedLock lock;
		bool finish;
		bool checkFinishState() {
			lock.sharedLock();
			scope(exit) lock.sharedUnlock();
			assert((lock.count & ~SharedLock.Exclusive) > 0);

			return finish;
		}

		void waitForFinish() {
			while (!checkFinishState()) {
				import sys.posix.sched;
				sched_yield();
			}
		}

		void signalFinish() {
			lock.exclusiveLock();
			assert(lock.mutex.isHeld(), "Mutex not held!");
			assert(lock.count == SharedLock.Exclusive, "Not an exclusive lock!");
			scope(exit) lock.exclusiveUnlock();
			finish = true;
		}
	}

	State state;
	assert(state.lock.count == 0);
	assert(!state.checkFinishState());
	assert(state.lock.count == 0);
	state.lock.sharedLock();
	assert(state.lock.count == 1);
	assert(!state.lock.mutex.isHeld());
	state.lock.sharedLock();
	assert(state.lock.count == 2);
	state.lock.sharedUnlock();
	assert(state.lock.count == 1);
	pthread_t writer;
	static void* lockForWrite(void* ctx) {
		auto state = cast(State*) ctx;
		state.lock.exclusiveLock();
		return cast(void*) cast(size_t) state.lock.count;
	}

	auto r = pthread_create(&writer, null, lockForWrite, &state);
	assert(r == 0);
	while (true) {
		state.lock.mutex.lock();
		scope(exit) state.lock.mutex.unlock();
		if (state.lock.count > 1) {
			break;
		}

		import sys.posix.sched;
		sched_yield();
	}

	assert(state.lock.count == SharedLock.Exclusive + 1);
	state.lock.sharedUnlock();
	void* ret;
	pthread_join(writer, &ret);
	assert(cast(size_t) ret == SharedLock.Exclusive);
	state.lock.exclusiveUnlock();
	assert(state.lock.count == 0);

	// thread test
	static void* readerTest(void* ctx) {
		auto state = cast(State*) ctx;
		state.waitForFinish();
		return null;
	}

	pthread_t[50] ts;
	foreach (i; 0 .. ts.length) {
		r = pthread_create(&ts[i], null, readerTest, &state);
		assert(r == 0);
	}

	state.signalFinish();

	foreach (i; 0 .. ts.length) {
		pthread_join(ts[i], &ret);
	}
}
