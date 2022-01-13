module d.gc.bin;

enum InvalidBinID = 0xff;

struct Bin {
	import d.gc.run;
	RunDesc* current;

	import d.gc.rbtree;
	RBTree!(RunDesc, addrRunCmp) runTree;
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
		this.shift = cast(ubyte) (shift + 17);

		// XXX: out contract
		assert(this.shift == (this.shift & MaxShiftMask));

		auto tag = (itemSize >> shift) & 0x03;
		auto mulIndices = getMulIndices();
		this.mul = mulIndices[tag];
	}

	uint computeIndex(uint offset) const {
		return (offset * mul) >> shift;
	}
}

// FIXME: For some reason, this is crashing.
// enum MaxShiftMask = cast(uint) ((size_t.sizeof * 8) - 1);
enum MaxShiftMask = 63;

/**
 * This is a bunch of magic values used to avoid requiring
 * division to find the index of an item within a run.
 *
 * Computed using finddivisor.d
 */
auto getMulIndices() {
	ushort[4] mul;
	mul[0] = 32768;
	mul[1] = 26215;
	mul[2] = 21846;
	mul[3] = 18725;
	return mul;
}

import d.gc.sizeclass;
immutable BinInfo[ClassCount.Small] binInfos = getBinInfos();
