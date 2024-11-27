module d.gc.threadpool;

struct ThreadPool {
private:
	import d.sync.mutex;
	Mutex mutex;

	// How many threads are executing.
	uint activeThreads;
	bool exitFlag;

	import core.stdc.pthread;
	pthread_t[] threads;

	// Current work to do.
	void delegate(uint) work;
	// How many threads should execute the work
	uint scheduled;

	static void* threadEntry(void* ctx) {
		// detach this thread -- it should not be scanned or stopped.
		import d.gc.thread;
		detachSelf();
		auto pool = cast(shared(ThreadPool*)) ctx;
		pool.executeWork();
		return null;
	}

public:

	void startThreads(pthread_t[] threadBuffer) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(ThreadPool*) &this).startThreadsImpl(threadBuffer);
	}

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

	void waitForIdle() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		auto tp = cast(ThreadPool*) &this;
		mutex.waitFor(tp.allThreadsIdle);
	}

	// joinAllThreads after current work is done
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
		this.threads = threadBuffer;
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
