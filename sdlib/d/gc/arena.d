module d.gc.arena;

import d.gc.sizeclass;
import d.gc.spec;
import d.gc.emap;

shared Arena gArena;

struct Arena {
	import d.gc.base;
	Base base;

	import d.gc.allocator;
	Allocator _allocator;

	@property
	shared(Allocator)* allocator() shared {
		auto a = &_allocator;

		if (a.regionAllocator is null) {
			import d.gc.region;
			a.regionAllocator = gRegionAllocator;

			import d.gc.emap;
			a.emap = gExtentMap;
		}

		return a;
	}

	import d.gc.bin;
	Bin[ClassCount.Small] bins;

	/**
	 * Small allocation facilities.
	 */
	void* allocSmall(size_t size) shared {
		// TODO: in contracts
		assert(size <= SizeClass.Small);
		if (size == 0) {
			return null;
		}

		auto sizeClass = getSizeClass(size);
		assert(sizeClass < ClassCount.Small);

		return bins[sizeClass].alloc(&this, sizeClass);
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(size_t size, bool zero) shared {
		// FIXME: in contracts.
		assert(size > SizeClass.Small);

		import d.gc.util;
		uint pages = (alignUp(size, PageSize) >> LgPageSize) & uint.max;
		auto e = allocator.allocPages(&this, pages);
		return e.addr;
	}

	/**
	 * Deallocation facility.
	 */
	void free(PageDescriptor pd, void* ptr) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.extent.contains(ptr), "invalid ptr!");
		assert(pd.extent.arena is &this, "Invalid arena!");

		import sdc.intrinsics;
		if (unlikely(!pd.isSlab()) || bins[pd.sizeClass].free(&this, ptr, pd)) {
			allocator.freePages(pd.extent);
		}
	}
}
