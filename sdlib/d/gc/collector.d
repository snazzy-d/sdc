module d.gc.collector;

import d.gc.arena;
import d.gc.emap;
import d.gc.spec;
import d.gc.tcache;

struct Collector {
	ThreadCache* treadCache;

	this(ThreadCache* tc) {
		this.treadCache = tc;
	}

	@property
	ref CachedExtentMap emap() {
		return threadCache.emap;
	}

	bool maybeRunGCCycle() {
		return gCollectorState.maybeRunGCCycle(this);
	}

	void runGCCycle() {
		import d.gc.thread;
		stopTheWorld();
		scope(exit) restartTheWorld();

		import d.gc.global;
		auto gcCycle = gState.nextGCCycle();

		import d.gc.region;
		auto dataRange = gDataRegionAllocator.computeAddressRange();
		auto ptrRange = gPointerRegionAllocator.computeAddressRange();

		import d.gc.range;
		auto managedAddressSpace = merge(dataRange, ptrRange);

		prepareGCCycle();

		import d.gc.scanner;
		shared(Scanner) scanner = Scanner(gcCycle, managedAddressSpace);

		// Go on and on until all worklists are empty.
		scanner.mark();

		/**
		 * We might have allocated, and therefore refilled the bin
		 * during the collection process. As a result, slots in the
		 * bins may not be makred at this point.
		 * 
		 * The straightforward way to handle this is simply to flush
		 * the bins.
		 * 
		 * Alternatively, we could make sure the slots are marked.
		 */
		threadCache.flushCache();

		collect(gcCycle);
	}

	void prepareGCCycle() {
		foreach (i; 0 .. ArenaCount) {
			import d.gc.arena;
			auto a = Arena.getIfInitialized(i);
			if (a !is null) {
				a.prepareGCCycle(emap);
			}
		}
	}

	void collect(ubyte gcCycle) {
		foreach (i; 0 .. ArenaCount) {
			import d.gc.arena;
			auto a = Arena.getIfInitialized(i);
			if (a !is null) {
				a.collect(emap, gcCycle);
			}
		}
	}
}

private:
struct CollectorState {
private:
	import d.sync.mutex;
	Mutex mutex;

	// This makes for a 32MB default target.
	size_t targetPageCount = 32 * 1024 * 1024 / PageSize;

public:
	bool maybeRunGCCycle(ref Collector collector) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(CollectorState*) &this).maybeRunGCCycleImpl(collector);
	}

private:
	bool maybeRunGCCycleImpl(ref Collector collector) {
		if (!needCollection()) {
			return false;
		}

		collector.runGCCycle();

		updateTargetPageCount();
		return true;
	}

	bool needCollection() {
		size_t totalUsedPageCount;

		foreach (i; 0 .. ArenaCount) {
			import d.gc.arena;
			auto a = Arena.getIfInitialized(i);
			if (a is null) {
				continue;
			}

			totalUsedPageCount += a.usedPages;
			if (totalUsedPageCount >= targetPageCount) {
				return true;
			}
		}

		return false;
	}

	size_t updateTargetPageCount() {
		size_t totalUsedPageCount;

		foreach (i; 0 .. ArenaCount) {
			import d.gc.arena;
			auto a = Arena.getIfInitialized(i);
			if (a is null) {
				continue;
			}

			totalUsedPageCount += a.usedPages;
		}

		return targetPageCount = 2 * totalUsedPageCount;
	}
}

shared CollectorState gCollectorState;
