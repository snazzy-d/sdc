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

	uint batchAllocate(shared(Arena)* arena, shared(ExtentMap)* emap,
	                   ubyte sizeClass, void*[] buffer) shared {
		import d.gc.sizeclass;
		assert(sizeClass < ClassCount.Small);
		assert(&arena.bins[sizeClass] == &this, "Invalid arena or sizeClass!");

		// Load eagerly as prefetching.
		import d.gc.slab;
		auto size = binInfos[sizeClass].itemSize;

		mutex.lock();
		scope(exit) mutex.unlock();

		auto remainBuffer = buffer;

		while (remainBuffer.length > 0) {
			auto slab = (cast(Bin*) &this).getSlab(arena, emap, sizeClass);
			if (slab is null) {
				break;
			}

			assert(slab.freeSlots > 0);
			auto filled = slab.batchAllocate(remainBuffer, size);

			remainBuffer = remainBuffer[filled .. remainBuffer.length];
		}

		return cast(uint) (buffer.length - remainBuffer.length);
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

unittest batchAllocation {
	import d.gc.util;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.emap;
	static shared ExtentMap emap;
	emap.tree.base = base;

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;

	void*[2048] buffer;

	auto checkSlotAndGetPd(void* ptr) {
		assert(ptr !is null);
		auto aptr = alignDown(ptr, PageSize);
		auto pd = emap.lookup(aptr);
		return pd;
	}

	// Basic test: confirm that we get the expected batch of slots
	import d.gc.slab;
	import d.gc.sizeclass;
	foreach (expectedSlabs; [1, 3, 4]) {
		foreach (sc; [0, 2, 6, 12, 38]) {
			auto expectedAllocsPerSlab = binInfos[sc].slots;
			auto wantSlots = expectedSlabs * expectedAllocsPerSlab;
			auto size = getSizeFromClass(sc);

			auto gotSlots = arena.bins[sc]
			                     .batchAllocate(&arena, &emap, cast(ubyte) sc,
			                                    buffer[0 .. wantSlots]);

			assert(gotSlots == wantSlots);

			uint countExtents = 0;
			PageDescriptor prevPd;

			foreach (i; 0 .. gotSlots) {
				auto ptr = buffer[i];
				auto pd = checkSlotAndGetPd(ptr);
				auto e = pd.extent;

				if (e !is prevPd.extent) {
					assert(e.freeSlots == 0);
					assert(ptr == e.address);
					countExtents++;
				} else {
					auto index = i % expectedAllocsPerSlab;
					assert(ptr == e.address + size * index);
				}

				prevPd = pd;
			}

			assert(countExtents == expectedSlabs);
		}
	}

	// "Checkerboard" test
	foreach (sc; [0, 2, 6, 12, 38]) {
		auto wantSlots = binInfos[sc].slots;
		auto size = getSizeFromClass(sc);

		// Get a slab's worth of slots:
		auto gotSlots = arena.bins[sc]
		                     .batchAllocate(&arena, &emap, cast(ubyte) sc,
		                                    buffer[0 .. wantSlots]);

		assert(gotSlots == wantSlots);

		auto slabPd = checkSlotAndGetPd(buffer[0]);
		auto slab = slabPd.extent.address;

		// Confirm that they're all actually on one slab:
		foreach (i; 0 .. gotSlots) {
			auto ptr = buffer[i];
			auto pd = checkSlotAndGetPd(ptr);
			assert(ptr == slab + size * i);
			assert(pd.extent.address == slab);
		}

		// Free only the even slots:
		foreach (i; 0 .. gotSlots / 2) {
			auto ptr = buffer[i * 2];
			assert(ptr == slab + size * (i * 2));
			auto pd = checkSlotAndGetPd(ptr);
			arena.free(&emap, pd, ptr);
		}

		// Ask for half the slot count, intend to reoccupy the even slots:
		auto wantEvenSlots = gotSlots / 2;
		auto gotEvenSlots = arena.bins[sc]
		                         .batchAllocate(&arena, &emap, cast(ubyte) sc,
		                                        buffer[0 .. wantEvenSlots]);

		assert(gotEvenSlots == wantEvenSlots);

		foreach (i; 0 .. gotEvenSlots) {
			auto ptr = buffer[i];
			auto pd = checkSlotAndGetPd(ptr);
			assert(pd.extent.address == slab);
			// Confirm that these all went in the slab slots we freed earlier:
			assert(ptr == slab + size * (i * 2));
			arena.free(&emap, pd, ptr);
		}
	}
}
