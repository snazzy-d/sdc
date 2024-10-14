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

	bool maybeRunGCCycle(ref size_t delta, ref size_t target) {
		return gCollectorState.maybeRunGCCycle(this, delta, target);
	}

	void runGCCycle() {
		gCollectorState.mutex.lock();
		scope(exit) gCollectorState.mutex.unlock();

		runGCCycleLocked();
	}

private:
	void runGCCycleLocked() {
		assert(gCollectorState.mutex.isHeld(), "Mutex not held!");
		assert(!threadCache.state.busy, "Cannot run GC cycle while busy!");

		// Make sure we do not try to collect during a collection.
		auto oldGCActivationState = threadCache.activateGC(false);
		scope(exit) threadCache.activateGC(oldGCActivationState);

		import d.gc.thread;
		stopTheWorld();
		scope(exit) restartTheWorld();

		import d.gc.global;
		auto gcCycle = gState.nextGCCycle();

		import d.gc.region;
		auto dataRange = gDataRegionAllocator.computeAddressRange();
		auto ptrRange = gPointerRegionAllocator.computeAddressRange();

		import d.gc.range;
		auto managedAddressSpace = dataRange.merge(ptrRange);

		prepareGCCycle();

		import d.gc.scanner;
		shared(Scanner) scanner = Scanner(gcCycle, managedAddressSpace);

		// Go on and on until all worklists are empty.
		scanner.mark();

		/**
		 * We might have allocated, and therefore refilled the bin
		 * during the collection process. As a result, slots in the
		 * bins may not be marked at this point.
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
	enum DefaultHeapSize = 32 * 1024 * 1024 / PageSize;

	size_t minHeapTarget = DefaultHeapSize;
	size_t nextTarget = DefaultHeapSize;

	size_t baseline = DefaultHeapSize;
	size_t peak = DefaultHeapSize;

public:
	bool maybeRunGCCycle(ref Collector collector, ref size_t delta,
	                     ref size_t target) shared {
		// Do not unnecessarily create contention on this mutex.
		if (!mutex.tryLock()) {
			delta = 0;
			target = 0;
			return false;
		}

		scope(exit) mutex.unlock();
		return (cast(CollectorState*) &this)
			.maybeRunGCCycleImpl(collector, delta, target);
	}

private:
	bool maybeRunGCCycleImpl(ref Collector collector, ref size_t delta,
	                         ref size_t target) {
		if (!needCollection(delta)) {
			target = delta;
			return false;
		}

		collector.runGCCycleLocked();

		target = updateTargetPageCount();
		return true;
	}

	bool needCollection(ref size_t delta) {
		auto total = Arena.computeUsedPageCount();

		if (total >= nextTarget) {
			// How much did we overshoot?
			delta = total - nextTarget;
			return true;
		}

		// How many more pages before we need a collection.
		delta = nextTarget - total;
		return false;
	}

	size_t updateTargetPageCount() {
		auto total = Arena.computeUsedPageCount();

		// This creates a low pass filter.
		static next(size_t base, size_t n) {
			return base - (base >> 3) + (n >> 3);
		}

		import d.gc.util;
		peak = max(next(peak, total), total);
		baseline = next(baseline, total);

		// Peak target at 1.5x the peak to prevent heap explosion.
		auto tpeak = peak + (peak >> 1);

		// Baseline target at 2x so we don't shrink the heap too fast.
		auto tbaseline = 2 * baseline;

		// We set the target at 1.75x the current heap size in pages.
		auto target = total + (total >> 1) + (total >> 2);

		// Clamp the target using tpeak and tbaseline.
		target = max(target, tbaseline);
		target = min(target, tpeak);

		nextTarget = max(target, minHeapTarget);
		return nextTarget - total;
	}
}

shared CollectorState gCollectorState;
