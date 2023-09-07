module d.gc.slab;

import d.gc.emap;
import d.gc.extent;
import d.gc.spec;

enum InvalidBinID = 0xff;

struct SlabAllocGeometry {
	Extent* e;
	void* address;
	size_t size;
	uint index;
	uint sizeClass;

	this(void* ptr, PageDescriptor pd) {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.isSlab(), "Expected a slab!");
		assert(pd.extent.contains(ptr), "ptr not in slab!");

		sizeClass = pd.sizeClass;

		import d.gc.util;
		auto offset = alignDownOffset(ptr, PageSize) + pd.index * PageSize;
		index = binInfos[sizeClass].computeIndex(offset);

		auto base = ptr - offset;
		assert(ptr is base + index * binInfos[sizeClass].itemSize);
		size = binInfos[sizeClass].itemSize;
		address = base + index * size;
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
