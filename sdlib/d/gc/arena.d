module d.gc.arena;

import d.gc.spec;

extern(C) void* __sd_gc_tl_malloc(size_t size) {
	return tl.alloc(size);
}

extern(C) void* __sd_gc_tl_array_alloc(size_t size) {
	return __sd_gc_tl_malloc(size);
}

extern(C) void _tl_gc_free(void* ptr) {
	tl.free(ptr);
}

extern(C) void* _tl_gc_realloc(void* ptr, size_t size) {
	return tl.realloc(ptr, size);
}

extern(C) void _tl_gc_set_stack_bottom(const void* bottom) {
	// tl.stackBottom = makeRange(bottom[]).ptr;
	// tl.stackBottom = makeRange(bottom[0 .. 0]).ptr;
}

extern(C) void _tl_gc_add_roots(const void[] range) {
	(cast(Arena*) &tl).addRoots(range);
}

extern(C) void _tl_gc_collect() {
	// tl.collect();
}

shared Arena tl;

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

	// const(void*)* stackBottom;
	const(void*)[][] roots;

	import d.gc.bin, d.gc.sizeclass;
	Bin[ClassCount.Small] bins;

	void* alloc(size_t size) shared {
		if (size <= SizeClass.Small) {
			return allocSmall(size);
		}

		return allocLarge(size, false);
	}

	void* calloc(size_t size) shared {
		if (size <= SizeClass.Small) {
			auto ret = allocSmall(size);
			memset(ret, 0, size);
			return ret;
		}

		return allocLarge(size, true);
	}

	void free(void* ptr) shared {
		if (ptr is null) {
			return;
		}

		import d.gc.util;
		auto aptr = alignDown(ptr, PageSize);

		auto a = allocator;
		auto pd = a.emap.lookup(aptr);
		assert(pd.extent !is null);
		assert(pd.isSlab() || ptr is pd.extent.addr);

		if (!pd.isSlab() || bins[pd.sizeClass].free(&this, ptr, pd)) {
			a.freePages(pd.extent);
		}
	}

	void* realloc(void* ptr, size_t size) shared {
		if (size == 0) {
			free(ptr);
			return null;
		}

		if (ptr is null) {
			return alloc(size);
		}

		import d.gc.util;
		auto aptr = alignDown(ptr, PageSize);

		auto a = allocator;
		auto pd = a.emap.lookup(aptr);
		assert(pd.extent !is null);
		assert(pd.isSlab() || ptr is pd.extent.addr);

		auto copySize = size;
		if (pd.isSlab()) {
			auto newSizeClass = getSizeClass(size);
			auto oldSizeClass = pd.sizeClass;
			if (newSizeClass == oldSizeClass) {
				return ptr;
			}

			if (newSizeClass > oldSizeClass) {
				copySize = getSizeFromClass(oldSizeClass);
			}
		} else {
			auto esize = pd.extent.size;
			if (alignUp(size, PageSize) == esize) {
				return ptr;
			}

			// TODO: Try to extend/shrink in place.
			import d.gc.util;
			copySize = min(size, esize);
		}

		auto newPtr = alloc(size);
		if (newPtr is null) {
			return null;
		}

		memcpy(newPtr, ptr, copySize);

		if (!pd.isSlab() || bins[pd.sizeClass].free(&this, ptr, pd)) {
			a.freePages(pd.extent);
		}

		return newPtr;
	}

private:
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
	 * GC facilities
	 */
	void addRoots(const void[] range) {
		// FIXME: Casting to void* is aparently not handled properly :(
		auto ptr = cast(void*) roots.ptr;

		// We realloc everytime. It doesn't really matter at this point.
		roots.ptr = cast(const(void*)[]*) (cast(shared(Arena)*) &this)
			.realloc(ptr, (roots.length + 1) * void*[].sizeof);

		// Using .ptr to bypass bound checking.
		roots.ptr[roots.length] = makeRange(range);

		// Update the range.
		roots = roots.ptr[0 .. roots.length + 1];
	}

	void collect() {
		// TODO: The set need a range interface or some other way to iterrate.
		// FIXME: Prepare the GC so it has bitfields for all extent classes.

		// Scan the roots !
		__sdgc_push_registers(scanStack);
		foreach (range; roots) {
			scan(range);
		}

		// TODO: Go on and on until all worklists are empty.

		// TODO: Collect.
	}

	bool scanStack() {
		const(void*) p;

		auto iptr = cast(size_t) &p;
		// auto iend = cast(size_t) stackBottom;
		size_t iend = 0;
		auto length = (iend - iptr) / size_t.sizeof;

		auto range = (&p)[1 .. length];
		return scan(range);
	}

	bool scan(const(void*)[] range) {
		/*
		bool newPtr;
		foreach (ptr; range) {
			enum PtrMask = ~(AddressSpace - 1);
			auto iptr = cast(size_t) ptr;

			if (iptr & PtrMask) {
				// This is not a pointer, move along.
				// TODO: Replace this with a min-max test.
				continue;
			}

			import d.gc.util;
			auto aptr = alignDown(ptr, PageSize);

			auto a = allocator;
			auto pd = a.emap.lookup(aptr);
			if (pd.extent is null) {
				// We have no mappign there.
				continue;
			}

			// FIXME: We have something, mark!
		}

		return newPtr;
		/*/
		return false;
		// */
	}
}

private:

/**
 * This function get a void[] range and chnage it into a
 * const(void*)[] one, reducing to alignement boundaries.
 */
const(void*)[] makeRange(const void[] range) {
	size_t iptr = cast(size_t) range.ptr;
	auto aiptr = (((iptr - 1) / size_t.sizeof) + 1) * size_t.sizeof;

	// Align the ptr and remove the differnece from the length.
	auto aptr = cast(const(void*)*) aiptr;
	if (range.length < 8) {
		return aptr[0 .. 0];
	}

	auto length = (range.length - aiptr + iptr) / size_t.sizeof;
	return aptr[0 .. length];
}

extern(C):
version(OSX) {
	// For some reason OSX's symbol get a _ prepended.
	bool _sdgc_push_registers(bool delegate());
	alias __sdgc_push_registers = _sdgc_push_registers;
} else {
	bool __sdgc_push_registers(bool delegate());
}
