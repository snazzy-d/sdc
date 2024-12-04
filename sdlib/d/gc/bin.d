module d.gc.bin;

import d.gc.arena;
import d.gc.emap;
import d.gc.page;
import d.gc.slab;
import d.gc.spec;

import sdc.intrinsics;

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

	void** batchAllocate(
		shared(PageFiller)* filler,
		ref CachedExtentMap emap,
		ubyte sizeClass,
		void** top,
		void** bottom,
		size_t slotSize,
	) shared {
		import d.gc.sizeclass;
		assert(isSmallSizeClass(sizeClass), "Invalid size class!");
		assert(&filler.arena.bins[sizeClass] is &this,
		       "Invalid arena or sizeClass!");
		assert(slotSize == binInfos[sizeClass].slotSize, "Invalid slot size!");

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this)
			.batchAllocateImpl(filler, emap, sizeClass, top, bottom, slotSize);
	}

	uint batchFree(const(void*)[] worklist, PageDescriptor* pds,
	               Extent** dallocSlabs, ref uint ndalloc) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this)
			.batchFreeImpl(worklist, pds, dallocSlabs, ndalloc);
	}

private:
	void** batchAllocateImpl(
		shared(PageFiller)* filler,
		ref CachedExtentMap emap,
		ubyte sizeClass,
		void** top,
		void** bottom,
		size_t slotSize,
	) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");
		assert(bottom < top, "Invalid stack boundaries!");
		assert((top - bottom) < uint.max, "Invalid stack size!");

		auto insert = bottom;
		while (insert !is top) {
			assert(insert < top, "Insert out of bounds!");

			auto e = getSlab(filler, emap, sizeClass);
			if (unlikely(e is null)) {
				break;
			}

			assert(e.nfree > 0);
			uint nfill = (top - insert) & uint.max;
			insert = e.batchAllocate(insert, nfill, slotSize);
			assert(bottom <= insert && insert <= top);

			// If the slab is not full, we are done.
			if (e.nfree > 0) {
				break;
			}

			// The slab is full, remove from the heap.
			slabs.remove(e);
		}

		return insert;
	}

	uint batchFreeImpl(const(void*)[] worklist, PageDescriptor* pds,
	                   Extent** dallocSlabs, ref uint ndalloc) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");
		assert(worklist.length > 0, "Worklist is empty!");

		uint ndeferred = 0;

		auto a = pds[0].arenaIndex;
		auto ec = pds[0].extentClass;
		auto bi = binInfos[ec.sizeClass];
		auto nslots = bi.nslots;

		foreach (i, ptr; worklist) {
			auto pd = pds[i];

			// This isn't the right arena, move on to the next slot.
			if (pd.arenaIndex != a) {
				worklist[ndeferred] = ptr;
				pds[ndeferred] = pd;
				ndeferred++;
				continue;
			}

			auto e = pd.extent;
			assert(e.contains(ptr), "ptr not in the Extent!");

			auto se = SlabEntry(pd, ptr);
			assert(se.computeAddress() is ptr,
			       "ptr does not point to the start of the slot!");

			e.free(se.index);

			auto nfree = e.nfree;
			if (nfree == nslots) {
				// If we only had one slot, we never got added to the heap.
				if (nslots > 1) {
					slabs.remove(e);
				}

				dallocSlabs[ndalloc++] = e;
				continue;
			}

			if (nfree == 1) {
				// Newly non empty.
				assert(nslots > 1);
				slabs.insert(e);
			}
		}

		return ndeferred;
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

		if (unlikely(slab is null)) {
			// Another thread might have been successful
			// while we did not hold the lock.
			return slabs.top;
		}

		// We may have allocated the slab we need when the lock was released.
		if (likely(slabs.top is null)) {
			slabs.insert(slab);
			return slab;
		}

		// We are about to release the freshly allocated slab.
		// We do not want another thread stealing the slab we intend
		// to use from under our feets, so we keep it around.
		auto current = slabs.pop();

		assert(slab !is current);
		assert(slab.nfree == binInfos[sizeClass].nslots);

		{
			// Release the lock while we release the slab.
			mutex.unlock();
			scope(exit) mutex.lock();

			filler.freeExtent(emap, slab);
		}

		// Now we put it back, which ensure we have at least one
		// slab available that we can return.
		slabs.insert(current);
		return slabs.top;
	}

/**
 * GC facilities.
 */
package:
	void clearForCollection() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(PriorityExtentHeap*) &slabs).clear();
	}

	void combineAfterCollection(ref PriorityExtentHeap cSlabs) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(PriorityExtentHeap*) &slabs).combine(cSlabs);
	}
}
