module d.gc.bin;

import d.gc.arena;
import d.gc.emap;
import d.gc.meta;
import d.gc.spec;

enum InvalidBinID = 0xff;

/**
 * A bin is used to keep track of runs of a certain
 * size class. There is one bin per small size class.
 */
struct Bin {
	import d.sync.mutex;
	shared Mutex mutex;

	import d.gc.extent;
	Extent* current;

	// XXX: We might want to consider targeting Extents
	// on old huge pages instead of just address.
	import d.gc.heap;
	Heap!(Extent, addrExtentCmp) slabs;

	void* alloc(shared(Arena)* arena, shared(ExtentMap)* emap, ubyte sizeClass,
	            size_t usedCapacity) shared {
		assert(isSmallSizeClass(sizeClass));
		assert(&arena.bins[sizeClass] == &this, "Invalid arena or sizeClass!");

		// Load eagerly as prefetching.
		auto size = binInfos[sizeClass].itemSize;

		Extent* slab;
		uint index;

		{
			mutex.lock();
			scope(exit) mutex.unlock();

			slab = (cast(Bin*) &this).getSlab(arena, emap, sizeClass);
			if (slab is null) {
				return null;
			}

			index = slab.allocate();
		}

		return slab.address + index * size;
	}

	struct slabAllocGeometry {
		Extent* e;
		uint sc;
		size_t size;
		uint index;
		void* address;

		this(void* ptr, PageDescriptor pd, bool ptrIsStart) {
			assert(pd.extent !is null, "Extent is null!");
			assert(pd.isSlab(), "Expected a slab!");
			assert(pd.extent.contains(ptr), "ptr not in slab!");

			e = pd.extent;
			sc = pd.sizeClass;

			import d.gc.util;
			auto offset = alignDownOffset(ptr, PageSize) + pd.index * PageSize;
			index = binInfos[sc].computeIndex(offset);

			auto base = ptr - offset;
			size = binInfos[sc].itemSize;
			address = base + index * size;

			assert(!ptrIsStart || (ptr is base + index * size),
			       "ptr does not point to start of slab alloc!");
		}
	}

	bool free(shared(Arena)* arena, void* ptr, PageDescriptor pd) shared {
		assert(&arena.bins[pd.sizeClass] == &this,
		       "Invalid arena or sizeClass!");

		auto sg = slabAllocGeometry(ptr, pd, true);
		auto slots = binInfos[sg.sc].slots;

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this).freeImpl(sg.e, sg.index, slots);
	}

	pInfo getInfo(shared(Arena)* arena, void* ptr, PageDescriptor pd) shared {
		assert(&arena.bins[pd.sizeClass] == &this,
		       "Invalid arena or sizeClass!");

		auto sg = slabAllocGeometry(ptr, pd, false);

		mutex.lock();
		scope(exit) mutex.unlock();

		// If label flag is 0, or this size class does not support labels,
		// then the alloc is reported to be fully used:
		if (!sg.e.hasLabel(sg.index)) {
			return pInfo(sg.address, sg.size, sg.size);
		}

		// Decode label, found in the final byte (or two bytes) of the alloc:
		auto body = (cast(ubyte*) sg.address);
		ubyte lo = body[sg.size - 1];
		ushort freeSize = lo >>> 1;
		if (lo & 1 != 0) {
			ushort hi = body[sg.size - 2];
			freeSize |= hi << 7;
		}

		return pInfo(sg.address, sg.size, sg.size - freeSize);
	}

	bool setInfo(shared(Arena)* arena, void* ptr, PageDescriptor pd,
	             size_t usedCapacity) shared {
		assert(&arena.bins[pd.sizeClass] == &this,
		       "Invalid arena or sizeClass!");

		auto sg = slabAllocGeometry(ptr, pd, true);

		mutex.lock();
		scope(exit) mutex.unlock();

		assert(usedCapacity <= sg.size,
		       "Used capacity may not exceed alloc size!");

		// If this size class does not support labels, then let the caller know
		// that the used capacity did not change, as it is permanently fixed:
		if (!sg.e.allowsLabels) {
			return false;
		}

		// If capacity of alloc is now fully used, there is no label:
		if (usedCapacity == sg.size) {
			sg.e.clearLabel(sg.index);
			return true;
		}

		// Encode label and write it to the last byte (or two bytes) of alloc:
		auto freeSize = sg.size - usedCapacity;
		enum mask = (1 << 7) - 1;
		ubyte hi = (freeSize >>> 7) & mask;
		ubyte hasHi = cast(ubyte) (hi != 0);
		ubyte lo = ((freeSize & mask) << 1) | hasHi;

		auto body = (cast(ubyte*) sg.address);
		body[sg.size - 1] = lo;
		if (hasHi) {
			body[sg.size - 2] = hi;
		}

		sg.e.setLabel(sg.index);
		return true;
	}

private:
	bool freeImpl(Extent* e, uint index, uint slots) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		e.free(index);

		auto nfree = e.freeSlots;
		if (nfree == slots) {
			if (e is current) {
				current = null;
				return true;
			}

			// If we only had one slot, we never got added to the heap.
			if (slots > 1) {
				slabs.remove(e);
			}

			return true;
		}

		if (nfree == 1 && e !is current) {
			// Newly non empty.
			assert(slots > 1);
			slabs.insert(e);
		}

		return false;
	}

	auto tryGetSlab() {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		// If the current slab still have free slots, go for it.
		if (current !is null && current.freeSlots != 0) {
			return current;
		}

		current = slabs.pop();
		return current;
	}

	auto getSlab(shared(Arena)* arena, shared(ExtentMap)* emap,
	             ubyte sizeClass) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		auto slab = tryGetSlab();
		if (slab !is null) {
			return slab;
		}

		{
			// Release the lock while we allocate a slab.
			mutex.unlock();
			scope(exit) mutex.lock();

			// We don't have a suitable slab, so allocate one.
			slab = arena.allocSlab(emap, sizeClass);
		}

		if (slab is null) {
			// Another thread might have been successful
			// while we did not hold the lock.
			return tryGetSlab();
		}

		// We may have allocated the slab we need when the lock was released.
		if (current is null || current.freeSlots == 0) {
			current = slab;
			return slab;
		}

		// If we have, then free the run we just allocated.
		assert(slab !is current);
		assert(current.freeSlots > 0);

		// In which case we put the free run back in the tree.
		assert(slab.freeSlots == binInfos[sizeClass].slots);
		arena.freeSlab(emap, slab);

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
