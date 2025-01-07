module d.sync.rwlock;

import d.sync.mutex;

/**
 * RWLock allows either one exclusive writer, or N readers. While any reader
 * has the lock, a writer must wait. While a writer is waiting, no new readers
 * are allowed to lock, but existing readers can unlock.
 */
struct RWLock {
private:
	shared Mutex mutex;
	uint count;
	enum uint Exclusive = 1 << 31;
public:
	/**
	 * Lock for reading.
	 *
	 * Can be locked for reading by any number of readers. No writers can
	 * acquire the lock until all readers have unlocked.
	 */
	void beginRead() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(RWLock*) &this).lockReadImpl();
	}

	void endRead() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(RWLock*) &this).unlockReadImpl();
	}

	/**
	 * Lock for writing.
	 *
	 * Locks exclusively for the calling thread.
	 */
	void beginWrite() shared {
		mutex.lock();

		(cast(RWLock*) &this).lockWriteImpl();
	}

	void endWrite() shared {
		assert(mutex.isHeld());
		scope(exit) mutex.unlock();

		(cast(RWLock*) &this).unlockWriteImpl();
	}

private:
	bool noWriteLock() {
		return count < Exclusive;
	}

	void lockReadImpl() {
		assert(mutex.isHeld());
		mutex.waitFor(noWriteLock);
		++count;
	}

	bool hasExclusiveLock() {
		return count == Exclusive;
	}

	void lockWriteImpl() {
		assert(mutex.isHeld());
		// Wait for no other exclusive lock.
		mutex.waitFor(noWriteLock);
		count += Exclusive;
		mutex.waitFor(hasExclusiveLock);
	}

	void unlockReadImpl() {
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
		shared RWLock lock;
		bool finish;
		bool checkFinishState() {
			lock.beginRead();
			scope(exit) lock.endRead();
			assert((lock.count & ~RWLock.Exclusive) > 0);

			return finish;
		}

		void waitForFinish() {
			while (!checkFinishState()) {
				import sys.posix.sched;
				sched_yield();
			}
		}

		void signalFinish() {
			lock.beginWrite();
			assert(lock.mutex.isHeld(), "Mutex not held!");
			assert(lock.count == RWLock.Exclusive, "Not an exclusive lock!");
			scope(exit) lock.endWrite();
			finish = true;
		}
	}

	State state;
	assert(state.lock.count == 0);
	assert(!state.checkFinishState());
	assert(state.lock.count == 0);
	state.lock.beginRead();
	assert(state.lock.count == 1);
	assert(!state.lock.mutex.isHeld());
	state.lock.beginRead();
	assert(state.lock.count == 2);
	state.lock.endRead();
	assert(state.lock.count == 1);
	pthread_t writer;
	static void* lockForWrite(void* ctx) {
		auto state = cast(State*) ctx;
		state.lock.beginWrite();
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

	assert(state.lock.count == RWLock.Exclusive + 1);
	state.lock.endRead();
	void* ret;
	pthread_join(writer, &ret);
	assert(cast(size_t) ret == RWLock.Exclusive);
	state.lock.endWrite();
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
