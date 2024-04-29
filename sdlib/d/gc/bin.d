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

	uint batchAllocate(
		shared(PageFiller)* filler,
		ref CachedExtentMap emap,
		ubyte sizeClass,
		void*[] buffer,
		size_t slotSize,
	) shared {
		import d.gc.sizeclass;
		assert(sizeClass < BinCount, "Invalid size class!");
		assert(&filler.arena.bins[sizeClass] is &this,
		       "Invalid arena or sizeClass!");
		assert(slotSize == binInfos[sizeClass].slotSize, "Invalid slot size!");

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Bin*) &this)
			.batchAllocateImpl(filler, emap, sizeClass, buffer, slotSize);
	}

	bool free(void* ptr, PageDescriptor pd) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.isSlab(), "Expected a slab!");
		assert(pd.extent.contains(ptr), "ptr not in slab!");

		auto ec = pd.extentClass;
		auto sc = ec.sizeClass;
		auto nslots = binInfos[sc].nslots;
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
			if (unlikely(e is null)) {
				break;
			}

			assert(e.nfree > 0);
			total += e.batchAllocate(buffer[total .. buffer.length], slotSize);

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
