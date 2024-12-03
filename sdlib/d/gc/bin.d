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

		assert(bottom < top, "Invalid stack boundaries!");
		assert((top - bottom) < uint.max, "Invalid stack size!");

		/**
		 * When we run out of slab with free space, we allocate a fresh slab.
		 * However, while we do so, another thread may have returned slabs to
		 * the bin, so we might end up not using our fresh slab.
		 */
		Extent* freshSlab = null;

		/**
		 * Allocating fresh slab might fail, for instance if the system
		 * runs out of memory. Before we attempt to allocate one, we make
		 * sure we made progress since the last attempt.
		 */
		bool progressed = true;

		/**
		 * We insert from the bottom up!
		 */
		auto insert = bottom;

		Refill: {
			mutex.lock();
			scope(exit) mutex.unlock();

			auto slabs = &(cast(Bin*) &this).slabs;

			while (insert !is top) {
				assert(insert < top, "Insert out of bounds!");

				auto e = slabs.top;
				if (unlikely(e is null)) {
					if (freshSlab !is null) {
						// We have a fresh slab, use it!
						slabs.insert(freshSlab);
						freshSlab = null;
						continue;
					}

					if (progressed) {
						// Let's go fetch a new fresh slab.
						goto FreshSlab;
					}

					break;
				}

				assert(e.nfree > 0);
				uint nfill = (top - insert) & uint.max;
				insert = e.batchAllocate(insert, nfill, slotSize);
				assert(bottom <= insert && insert <= top);

				progressed = true;

				// If the slab is not full, we are done.
				if (e.nfree > 0) {
					break;
				}

				// The slab is full, remove from the heap.
				slabs.remove(e);
				continue;
			}
		}

		if (freshSlab !is null) {
			filler.freeExtent(emap, freshSlab);
		}

		return insert;

	FreshSlab:
		assert(insert !is top);
		assert(freshSlab is null);
		assert(progressed);

		freshSlab = filler.allocSlab(emap, sizeClass);
		auto nslots = binInfos[sizeClass].nslots;
		assert(freshSlab is null || freshSlab.nfree == nslots);

		progressed = false;
		goto Refill;
	}

	uint batchFree(const(void*)[] worklist, PageDescriptor* pds,
	               Extent** dallocSlabs, ref uint ndalloc) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this)
			.batchFreeImpl(worklist, pds, dallocSlabs, ndalloc);
	}

private:
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
