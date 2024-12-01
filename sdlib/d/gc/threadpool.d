module d.gc.threadpool;

struct ThreadPool {
private:
	import d.sync.mutex;
	Mutex mutex;

	// How many threads are executing work.
	uint activeThreads;
	// Stop processing work, exit the thread.
	bool exitFlag;

	import core.stdc.pthread;
	pthread_t[] threads;

	// Current work to do.
	void delegate(uint) work;
	// How many threads should execute the work
	uint scheduled;

	static void* threadEntry(void* ctx) {
		// Detach this thread -- it should not be scanned or stopped.
		import d.gc.thread;
		detachSelf();
		auto pool = cast(shared(ThreadPool*)) ctx;
		pool.executeWork();
		return null;
	}

public:

	/**
	 * Start threads using the given thread buffer. All threads will wait
	 * for work dispatched to them using the `dispatch` function. Optimal
	 * thread buffer size should be number of cores, or number of cores - 1
	 * if you intend to not use the calling thread in the pool.
	 *
	 * Note that these threads will be marked as detached, so they will not
	 * be scanned if a GC cycle is run.
	 */
	void startThreads(pthread_t[] threadBuffer) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(ThreadPool*) &this).startThreadsImpl(threadBuffer);
	}

	/**
	 * Dispatch work to the threads. `count` instances of the `work`
	 * delegate are run, with each call to the delegate receiving an index
	 * from `0` to `count - 1`. If `count` is greater than the number of
	 * threads in the pool, threads will re-call the delegate, until
	 * `count` calls to the delegate are made. No ordering of the index is
	 * guaranteed, but it is guaranteed that only one instance of an index
	 * will be used.
	 *
	 * If you pass `true` for `useThisThread`, then the calling thread will
	 * also be given work, and this function will not return until all the
	 * work is scheduled.
	 */
	void dispatch(void delegate(uint) work, uint count,
	              bool useThisThread) shared {
		{
			mutex.lock();
			scope(exit) mutex.unlock();

			useThisThread = (cast(ThreadPool*) &this).dispatchImpl(work, count)
				&& useThisThread;
		}

		if (!useThisThread) {
			return;
		}

		// Utilize this thread to do some work as well.
		uint idx;
		while (getWorkMainThread(idx)) {
			work(idx);
		}
	}

	/**
	 * Wait for all work to be complete.
	 */
	void waitForIdle() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		auto tp = cast(ThreadPool*) &this;
		mutex.waitFor(tp.allThreadsIdle);
	}

	/**
	 * Stop all threads, and join them. If you need to start the thread
	 * pool up again, you can call `startThreads` again.
	 *
	 * Threads are not stopped until all scheduled work is completed.
	 */
	void joinAll() shared {
		{
			mutex.lock();
			scope(exit) mutex.unlock();

			(cast(ThreadPool*) &this).stopAllThreads();
		}

		(cast(ThreadPool*) &this).joinAllThreadsImpl();
	}

private:
	void startThreadsImpl(pthread_t[] threadBuffer) {
		assert(threads.length == 0);

		threads = threadBuffer;
		exitFlag = false;
		activeThreads = cast(uint) threadBuffer.length;
		foreach (ref tid; threads) {
			pthread_create(&tid, null, threadEntry, cast(void*) &this);
		}
	}

	bool dispatchImpl(void delegate(uint) work, uint count) {
		assert(mutex.isHeld(), "Mutex not held!");
		auto sharedThis = cast(shared(ThreadPool)*) &this;
		sharedThis.mutex.waitFor(noMoreWork);

		assert(scheduled == 0);

		this.work = work;
		this.scheduled = count;
		import core.stdc.stdio;

		// Return true if the current idle threads cannot consume all the work.
		return activeThreads + scheduled > threads.length;
	}

	void stopAllThreads() {
		assert(mutex.isHeld(), "Mutex not held!");
		auto sharedThis = cast(shared(ThreadPool)*) &this;
		sharedThis.mutex.waitFor(noMoreWork);
		assert(scheduled == 0);

		exitFlag = true;
		sharedThis.mutex.waitFor(allThreadsIdle);
	}

	void joinAllThreadsImpl() {
		assert(exitFlag);
		assert(scheduled == 0);
		assert(activeThreads == 0);
		void* ret;
		foreach (tid; threads) {
			pthread_join(tid, &ret);
		}

		threads = [];
	}

	bool noMoreWork() {
		return scheduled == 0;
	}

	bool allThreadsIdle() {
		return activeThreads == 0;
	}

	void executeWork() shared {
		void delegate(uint) workItem;
		uint idx;
		while (getWork(workItem, idx)) {
			workItem(idx);
		}
	}

	bool getWork(ref void delegate(uint) workItem, ref uint idx) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(ThreadPool*) &this).getWorkImpl(workItem, idx);
	}

	bool getWorkMainThread(ref uint idx) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(ThreadPool*) &this).getWorkMainThreadImpl(idx);
	}

	bool getWorkMainThreadImpl(ref uint idx) {
		assert(mutex.isHeld(), "Mutex not held!");

		if (scheduled == 0) {
			return false;
		}

		scheduled -= 1;
		idx = scheduled;
		return true;
	}

	bool getWorkImpl(ref void delegate(uint) workItem, ref uint idx) {
		assert(mutex.isHeld(), "Mutex not held!");

		assert(activeThreads > 0);
		activeThreads -= 1;

		auto sharedThis = cast(shared(ThreadPool)*) &this;
		sharedThis.mutex.waitFor(workReadyOrQuit);
		if (exitFlag) {
			return false;
		}

		assert(scheduled > 0);

		workItem = work;

		activeThreads += 1;
		scheduled -= 1;
		idx = scheduled;

		return true;
	}

	bool workReadyOrQuit() {
		return exitFlag || scheduled > 0;
	}
}

unittest threadpool {
	import core.stdc.pthread;
	import core.stdc.unistd;
	shared ThreadPool threadPool;
	pthread_t[128] threads;

	threadPool.startThreads(threads[0 .. threads.length]);
	scope(exit) threadPool.joinAll();

	assert(cast(pthread_t*) threadPool.threads.ptr is threads.ptr);
	assert(threadPool.threads.length == threads.length);

	uint[1000] data;
	foreach (i, ref v; data) {
		v = cast(uint) i;
	}

	void doubleIt(uint idx) {
		data[idx] *= 2;
	}

	threadPool.dispatch(doubleIt, data.length, false);

	threadPool.waitForIdle();
	assert(threadPool.activeThreads == 0);
	foreach (i, ref v; data) {
		assert(v == i * 2);
	}

	threadPool.dispatch(doubleIt, data.length, true);

	threadPool.waitForIdle();
	assert(threadPool.activeThreads == 0);

	foreach (i, ref v; data) {
		assert(v == i * 4);
	}

	// Test dispatching multiple tasks
	import d.sync.atomic;
	shared Atomic!uint sum;
	void otherTask(uint idx) {
		sleep(2);
		sum.fetchAdd(idx);
	}

	threadPool.dispatch(otherTask, 128, false);
	sleep(1);
	assert(threadPool.activeThreads == 128);
	assert(threadPool.scheduled == 0);
	threadPool.dispatch(doubleIt, data.length, true);
	threadPool.waitForIdle();
	assert(threadPool.activeThreads == 0);

	foreach (i, ref v; data) {
		assert(v == i * 8);
	}

	assert(sum.load() == 127 * 128 / 2);
}
