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

	// XXX: We might want to consider targeting Extents
	// on old blocks instead of just address.
	import d.gc.extent;
	AddrExtentHeap slabs;

	void* alloc(shared(Arena)* arena, ref CachedExtentMap emap,
	            ubyte sizeClass) shared {
		import d.gc.sizeclass;
		assert(sizeClass < ClassCount.Small);
		assert(&arena.bins[sizeClass] == &this, "Invalid arena or sizeClass!");

		// Load eagerly as prefetching.
		import d.gc.slab;
		auto slotSize = binInfos[sizeClass].itemSize;

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this).allocImpl(arena, emap, sizeClass, slotSize);
	}

	bool free(shared(Arena)* arena, void* ptr, PageDescriptor pd) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.isSlab(), "Expected a slab!");
		assert(pd.extent.contains(ptr), "ptr not in slab!");
		assert(&arena.bins[pd.sizeClass] == &this,
		       "Invalid arena or sizeClass!");

		import d.gc.slab;
		auto nslots = binInfos[pd.sizeClass].nslots;
		auto sg = SlabAllocGeometry(pd, ptr);
		assert(ptr is sg.address);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this).freeImpl(pd.extent, sg.index, nslots);
	}

private:
	void* allocImpl(shared(Arena)* arena, ref CachedExtentMap emap,
	                ubyte sizeClass, size_t slotSize) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getSlab(arena, emap, sizeClass);
		if (e is null) {
			return null;
		}

		void*[1] buffer = void;
		auto count = e.batchAllocate(buffer[0 .. 1], slotSize);
		assert(count > 0);

		// If the slab is full, remove it from the heap.
		if (e.nfree == 0) {
			slabs.remove(e);
		}

		return buffer[0];
	}

	bool freeImpl(Extent* e, uint index, uint nslots) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		e.free(index);

		auto nfree = e.nfree;
		if (nfree == nslots) {
			// If we only had one slot, we never got added to the heap.
			if (nslots > 1) {
				slabs.remove(e);
			}

			return true;
		}

		if (nfree == 1) {
			// Newly non empty.
			assert(nslots > 1);
			slabs.insert(e);
		}

		return false;
	}

	auto getSlab(shared(Arena)* arena, ref CachedExtentMap emap,
	             ubyte sizeClass) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		auto slab = slabs.top;
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

		auto current = slabs.top;
		if (slab is null) {
			// Another thread might have been successful
			// while we did not hold the lock.
			return current;
		}

		// We may have allocated the slab we need when the lock was released.
		if (current is null) {
			slabs.insert(slab);
			return slab;
		}

		// If we have, then free the run we just allocated.
		assert(slab !is current);
		assert(current.nfree > 0);

		// In which case we release the slab we just allocated.
		import d.gc.slab;
		assert(slab.nfree == binInfos[sizeClass].nslots);
		arena.freeSlab(emap, slab);

		// And use the metadata run.
		return current;
	}
}
