module d.gc.thread;

import d.gc.capi;
import d.gc.tcache;
import d.gc.tstate;
import d.gc.types;

void createProcess() {
	enterBusyState();
	scope(exit) exitBusyState();

	import d.gc.signal;
	setupSignals();

	initThread();

	import d.gc.hooks;
	__sd_gc_register_global_segments();
	__sd_gc_register_tls_segments();
}

void createThread() {
	enterBusyState();
	scope(exit) {
		exitBusyState();
		exitThreadCreation();
	}

	initThread();

	import d.gc.hooks;
	__sd_gc_register_tls_segments();
}

void destroyThread() {
	threadCache.destroyThread();
	gThreadState.remove(&threadCache);
}

void enterThreadCreation() {
	gThreadState.enterThreadCreation();
}

void exitThreadCreation() {
	gThreadState.exitThreadCreation();
}

uint getRegisteredThreadCount() {
	return gThreadState.getRegisteredThreadCount();
}

void enterBusyState() {
	threadCache.state.enterBusyState();
}

void exitBusyState() {
	threadCache.state.exitBusyState();
}

void stopTheWorld() {
	gThreadState.stopTheWorld();
}

void restartTheWorld() {
	gThreadState.restartTheWorld();
}

void scanSuspendedThreads(ScanDg scan) {
	gThreadState.scanSuspendedThreads(scan);
}

private:

void initThread() {
	assert(threadCache.state.busy, "Thread is not busy!");

	import d.gc.emap, d.gc.base;
	threadCache.initialize(&gExtentMap, &gBase);
	threadCache.activateGC();

	import d.gc.global;
	gThreadState.register(&threadCache);
}

struct ThreadState {
private:
	import d.sync.mutex;
	Mutex mutex;

	import d.sync.atomic;
	Atomic!uint startingThreadCount;
	uint registeredThreadCount = 0;

	RegisteredThreadRing registeredThreads;

	Mutex stopTheWorldMutex;

public:
	/**
	 * Thread management.
	 */
	void enterThreadCreation() shared {
		startingThreadCount.fetchAdd(1);
	}

	void exitThreadCreation() shared {
		auto s = startingThreadCount.fetchSub(1);
		assert(s > 0, "enterThreadCreation was not called!");
	}

	void register(ThreadCache* tcache) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(ThreadState*) &this).registerImpl(tcache);
	}

	void remove(ThreadCache* tcache) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(ThreadState*) &this).removeImpl(tcache);
	}

	auto getRegisteredThreadCount() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(ThreadState*) &this).registeredThreadCount;
	}

	void stopTheWorld() shared {
		import d.gc.hooks;
		__sd_gc_pre_stop_the_world_hook();

		stopTheWorldMutex.lock();

		while (suspendRunningThreads() || startingThreadCount.load() > 0) {
			import sys.posix.sched;
			sched_yield();
		}
	}

	void restartTheWorld() shared {
		while (resumeSuspendedThreads()) {
			import sys.posix.sched;
			sched_yield();
		}

		stopTheWorldMutex.unlock();

		import d.gc.hooks;
		__sd_gc_post_restart_the_world_hook();
	}

	void scanSuspendedThreads(ScanDg scan) shared {
		assert(stopTheWorldMutex.isHeld());

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(ThreadState*) &this).scanSuspendedThreadsImpl(scan);
	}

private:
	void registerImpl(ThreadCache* tcache) {
		registeredThreadCount++;
		registeredThreads.insert(tcache);
	}

	void removeImpl(ThreadCache* tcache) {
		registeredThreadCount--;
		registeredThreads.remove(tcache);
	}

	bool suspendRunningThreads() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(ThreadState*) &this).suspendRunningThreadsImpl();
	}

	bool suspendRunningThreadsImpl() {
		bool retry = false;

		auto r = registeredThreads.range;
		while (!r.empty) {
			auto tc = r.front;
			scope(success) r.popFront();

			// Make sure we do not self suspend!
			if (tc is &threadCache) {
				continue;
			}

			// If the thread isn't already stopped, we'll need to retry.
			auto ss = tc.state.suspendState;
			retry |= ss != SuspendState.Suspended;

			// If the thread has already been signaled.
			if (ss != SuspendState.None) {
				continue;
			}

			import d.gc.signal;
			signalThreadSuspend(tc);
		}

		return retry;
	}

	bool resumeSuspendedThreads() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(ThreadState*) &this).resumeSuspendedThreadsImpl();
	}

	bool resumeSuspendedThreadsImpl() {
		bool retry = false;

		auto r = registeredThreads.range;
		while (!r.empty) {
			auto tc = r.front;
			scope(success) r.popFront();

			// If the thread isn't already resumed, we'll need to retry.
			auto ss = tc.state.suspendState;
			retry |= ss != SuspendState.None;

			// If the thread isn't suspended, move on.
			if (ss != SuspendState.Suspended) {
				continue;
			}

			import d.gc.signal;
			signalThreadResume(tc);
		}

		return retry;
	}

	void scanSuspendedThreadsImpl(ScanDg scan) {
		auto r = registeredThreads.range;
		while (!r.empty) {
			auto tc = r.front;
			scope(success) r.popFront();

			// If the thread isn't suspended, move on.
			if (tc.state.suspendState != SuspendState.Suspended) {
				continue;
			}

			// Scan the registered TLS segments.
			foreach (s; tc.tlsSegments) {
				scan(s);
			}

			import d.gc.range;
			scan(makeRange(tc.stackTop, tc.stackBottom));
		}
	}
}

shared ThreadState gThreadState;
