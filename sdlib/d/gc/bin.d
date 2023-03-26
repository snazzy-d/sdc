module d.gc.bin;

import d.gc.arena;
import d.gc.spec;

enum InvalidBinID = 0xff;

/**
 * A bin is used to keep track of runs of a certain
 * size class. There is one bin per small size class.
 */
struct Bin {
	import d.sync.mutex;
	shared Mutex mutex;

	import d.gc.run;
	RunDesc* current;

	import d.gc.rbtree;
	RBTree!(RunDesc, addrRunCmp) runTree;

	void* allocSmall(Arena* arena, ubyte binID) {
		assert(binID < ClassCount.Small);
		assert(&arena.bins[binID] == &this, "Invalid arena or binID");

		mutex.lock();
		scope(exit) mutex.unlock();

		auto run = getRun(arena, binID);
		if (run is null) {
			return null;
		}

		// Load eagerly as prefetching.
		auto size = binInfos[binID].itemSize;
		auto index = run.small.allocate();
		auto base = cast(void*) &run.chunk.datas[run.runID];

		return base + size * index;
	}

private:
	auto tryGetRun() {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		// If the current run still have free slots, go for it.
		if (current !is null && current.small.freeSlots != 0) {
			return current;
		}

		// We ran out of free slots, ditch the current run and try
		// to find a new one in the tree.
		auto run = runTree.bestfit(null);
		if (run !is null) {
			// TODO: Extract node in one step.
			runTree.remove(run);
		}

		current = run;
		return run;
	}

	auto getRun(Arena* arena, ubyte binID) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		auto run = tryGetRun();
		if (run !is null) {
			return run;
		}

		{
			// Release the lock while we allocate a run.
			mutex.unlock();
			scope(exit) mutex.lock();

			// We don't have a suitable run, so allocate one.
			run = arena.allocateSmallRun(binID);
		}

		if (run is null) {
			// Another thread might have been successful
			// while we did not hold the lock.
			return tryGetRun();
		}

		// We may have allocated the run we need when allocating metadata.
		if (current is null || current.small.freeSlots == 0) {
			current = run;
			return run;
		}

		// If we haven, then free the run we just allocated.
		assert(run !is current);
		assert(current.small.freeSlots > 0);

		// In which case we put the free run back in the tree.
		assert(run.small.freeSlots == binInfos[binID].slots);
		arena.freeRun(run.chunk, run.runID, binInfos[binID].needPages);

		// And use the metadata run.
		return current;
	}
}

struct BinInfo {
	ushort itemSize;
	ushort slots;
	ubyte needPages;
	ubyte shift;
	ushort mul;

	this(ushort itemSize, ubyte shift, ubyte needPages, ushort slots) {
		this.itemSize = itemSize;
		this.slots = slots;
		this.needPages = needPages;
		this.shift = (shift + 17) & 0xff;

		// XXX: out contract
		enum MaxShiftMask = (8 * size_t.sizeof) - 1;
		assert(this.shift == (this.shift & MaxShiftMask));

		/**
		 * This is a bunch of magic values used to avoid requiring
		 * division to find the index of an item within a run.
		 *
		 * Computed using finddivisor.d
		 */
		ushort[4] mulIndices = [32768, 26215, 21846, 18725];
		auto tag = (itemSize >> shift) & 0x03;
		this.mul = mulIndices[tag];
	}

	uint computeIndex(size_t offset) const {
		// FIXME: in contract.
		assert(offset < needPages * PageSize, "Offset out of bounds!");

		return cast(uint) ((offset * mul) >> shift);
	}
}

import d.gc.sizeclass;
immutable BinInfo[ClassCount.Small] binInfos = getBinInfos();
