module d.gc.bin;

enum InvalidBinID = 0xff;

/**
 * A bin is used to keep track of runs of a certain
 * size class. There is one bin per small size class.
 */
struct Bin {
	import d.gc.run;
	RunDesc* current;

	import d.gc.rbtree;
	RBTree!(RunDesc, addrRunCmp) runTree;

	auto getRun() {
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

	uint computeIndex(uint offset) const {
		return (offset * mul) >> shift;
	}
}

// FIXME: For some reason, this is crashing.
// enum uint MaxShiftMask = (8 * size_t.sizeof) - 1;
enum uint MaxShiftMask = 63;

import d.gc.sizeclass;
immutable BinInfo[ClassCount.Small] binInfos = getBinInfos();
