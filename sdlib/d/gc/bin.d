module d.gc.bin;

import d.gc.arena;
import d.gc.emap;
import d.gc.spec;

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

	uint alloc(shared(Arena)* arena, shared(ExtentMap)* emap, ubyte sizeClass,
	           void*[] allocs) shared {
		import d.gc.sizeclass;
		assert(sizeClass < ClassCount.Small);
		assert(&arena.bins[sizeClass] == &this, "Invalid arena or sizeClass!");

		// Load eagerly as prefetching.
		import d.gc.slab;
		auto size = binInfos[sizeClass].itemSize;

		Extent* slab;
		uint allocCount;

		{
			mutex.lock();
			scope(exit) mutex.unlock();

			slab = (cast(Bin*) &this).getSlab(arena, emap, sizeClass);
			if (slab is null) {
				return 0;
			}

			import d.gc.util;
			auto wantSlots = min(cast(uint) allocs.length, slab.freeSlots);
			allocCount = slab.allocateBulk(allocs[0 .. wantSlots]);
		}

		return allocCount;
	}

	bool free(shared(Arena)* arena, void* ptr, PageDescriptor pd) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.isSlab(), "Expected a slab!");
		assert(pd.extent.contains(ptr), "ptr not in slab!");
		assert(&arena.bins[pd.sizeClass] == &this,
		       "Invalid arena or sizeClass!");

		import d.gc.slab;
		auto sg = SlabAllocGeometry(pd, ptr);
		assert(ptr is sg.address);

		auto slots = binInfos[pd.sizeClass].slots;

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this).freeImpl(pd.extent, sg.index, slots);
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
		import d.gc.slab;
		assert(slab.freeSlots == binInfos[sizeClass].slots);
		arena.freeSlab(emap, slab);

		// And use the metadata run.
		return current;
	}
}
