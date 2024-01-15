module d.gc.bin;

import d.gc.arena;
import d.gc.emap;
import d.gc.page;
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
	PriorityExtentHeap slabs;

	uint batchAllocate(
		shared(PageFiller)* filler,
		ref CachedExtentMap emap,
		ubyte sizeClass,
		void*[] buffer,
		size_t slotSize,
	) shared {
		import d.gc.sizeclass;
		assert(sizeClass < ClassCount.Small);
		assert(&filler.arena.bins[sizeClass] is &this,
		       "Invalid arena or sizeClass!");

		import d.gc.slab;
		assert(slotSize == binInfos[sizeClass].itemSize, "Invalid slot size!");

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this)
			.batchAllocateImpl(filler, emap, sizeClass, buffer, slotSize);
	}

	bool free(void* ptr, PageDescriptor pd) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.isSlab(), "Expected a slab!");
		assert(pd.extent.contains(ptr), "ptr not in slab!");

		import d.gc.slab;
		auto nslots = binInfos[pd.sizeClass].nslots;
		auto sg = SlabAllocGeometry(pd, ptr);
		assert(ptr is sg.address);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this).freeImpl(pd.extent, sg.index, nslots);
	}

private:
	uint batchAllocateImpl(shared(PageFiller)* filler, ref CachedExtentMap emap,
	                       ubyte sizeClass, void*[] buffer, size_t slotSize) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");

		uint total = 0;

		while (total < buffer.length) {
			auto e = getSlab(filler, emap, sizeClass);
			if (e is null) {
				break;
			}

			total += e.batchAllocate(buffer[total .. buffer.length], slotSize);

			// If the slab is not full, we are done.
			if (e.nfree > 0) {
				break;
			}

			// The slab is full, remove from the heap.
			slabs.remove(e);
		}

		return total;
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

	auto getSlab(shared(PageFiller)* filler, ref CachedExtentMap emap,
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
			slab = filler.allocSlab(emap, sizeClass);
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
		filler.freeSlab(emap, slab);

		// And use the metadata run.
		return current;
	}
}
