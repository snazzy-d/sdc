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
		void** insert,
		void** bottom,
		size_t slotSize,
	) shared {
		import d.gc.sizeclass;
		assert(sizeClass < BinCount, "Invalid size class!");
		assert(&filler.arena.bins[sizeClass] is &this,
		       "Invalid arena or sizeClass!");
		assert(slotSize == binInfos[sizeClass].slotSize, "Invalid slot size!");

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this).batchAllocateImpl(filler, emap, sizeClass,
		                                            insert, bottom, slotSize);
	}

	uint batchFree(const(void*)[] worklist, PageDescriptor* pds,
	               Extent** dallocSlabs, ref uint dallocCount) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this)
			.batchFreeImpl(worklist, pds, dallocSlabs, dallocCount);
	}

private:
	void** batchAllocateImpl(
		shared(PageFiller)* filler,
		ref CachedExtentMap emap,
		ubyte sizeClass,
		void** insert,
		void** bottom,
		size_t slotSize,
	) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");
		assert(insert > bottom, "Invalid stack boundaries!");
		assert((insert - bottom) < uint.max, "Invalid stack size!");

		while (insert > bottom) {
			auto e = getSlab(filler, emap, sizeClass);
			if (unlikely(e is null)) {
				break;
			}

			assert(e.nfree > 0);
			uint nfill = (insert - bottom) & uint.max;
			insert = e.batchAllocate(insert, nfill, slotSize);

			// If the slab is not full, we are done.
			if (e.nfree > 0) {
				// We get away with keeping the slab in the heap while allocating
				// because we know it is the best slab, and removing free slots
				// from it only increases its priority.
				break;
			}

			// The slab is full, remove from the heap.
			slabs.remove(e);
		}

		/**
		 * Note: If we are worried about security, we might want to shuffle
		 *       our allocations around. This makes the uses of techniques
		 *       like Heap feng Shui difficult.
		 *       We do not think it is worth the complication and performance
		 *       hit in the general case, but something we might want to add
		 *       in the future for security sensitive applications.
		 * 
		 * http://www.phreedom.org/research/heap-feng-shui/heap-feng-shui.html
		 */

		assert(insert >= bottom);
		return insert;
	}

	uint batchFreeImpl(const(void*)[] worklist, PageDescriptor* pds,
	                   Extent** dallocSlabs, ref uint dallocCount) {
		// FIXME: in contract.
		assert(mutex.isHeld(), "Mutex not held!");
		assert(worklist.length > 0, "Worklist is empty!");

		uint ndeferred = 0;

		auto a = pds[0].arenaIndex;
		auto ec = pds[0].extentClass;
		auto bi = binInfos[ec.sizeClass];

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

			if (freeImpl(e, se.index, bi.nslots)) {
				dallocSlabs[dallocCount++] = e;
			}
		}

		return ndeferred;
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

		(cast(Bin*) &this).clearForCollectionImpl();
	}

	void combineAfterCollection(ref PriorityExtentHeap cSlabs) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Bin*) &this).combineAfterCollectionImpl(cSlabs);
	}

private:
	void clearForCollectionImpl() {
		slabs.clear();
	}

	void combineAfterCollectionImpl(ref PriorityExtentHeap cSlabs) {
		slabs.combine(cSlabs);
	}
}
