module d.gc.tl;

import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

extern(C) void* __sd_gc_tl_malloc(size_t size) {
	return tc.alloc(size);
}

extern(C) void* __sd_gc_tl_array_alloc(size_t size) {
	return __sd_gc_tl_malloc(size);
}

extern(C) void _tl_gc_free(void* ptr) {
	tc.free(ptr);
}

extern(C) void* _tl_gc_realloc(void* ptr, size_t size) {
	return tc.realloc(ptr, size);
}

extern(C) void _tl_gc_set_stack_bottom(const void* bottom) {
	tc.stackBottom = makeRange(bottom[0 .. 0]).ptr;
}

extern(C) void _tl_gc_add_roots(const void[] range) {
	tc.addRoots(range);
}

extern(C) void _tl_gc_collect() {
	tc.collect();
}

ThreadCache tc;

struct ThreadCache {
private:
	import d.gc.emap;
	shared(ExtentMap)* emap;

	import d.gc.arena;
	shared(Arena)* arena;

	const(void)* stackBottom;
	const(void*)[][] roots;

public:
	void* alloc(size_t size) {
		initializeArena();

		if (size > 0 && size <= Arena.MaxSmallAllocSize) {
			return arena.allocSmall(emap, size);
		}

		return arena.allocLarge(emap, size, false);
	}

	void* calloc(size_t size) {
		initializeArena();

		if (size > 0 && size <= Arena.MaxSmallAllocSize) {
			auto ret = arena.allocSmall(emap, size);
			memset(ret, 0, size);
			return ret;
		}

		return arena.allocLarge(emap, size, true);
	}

	void free(void* ptr) {
		if (ptr is null) {
			return;
		}

		auto pd = getPageDescriptor(ptr);
		pd.extent.arena.free(emap, pd, ptr);
	}

	void* realloc(void* ptr, size_t size) {
		if (size == 0) {
			free(ptr);
			return null;
		}

		if (ptr is null) {
			return alloc(size);
		}

		auto copySize = size;
		auto pd = getPageDescriptor(ptr);

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
		pd.extent.arena.free(emap, pd, ptr);

		return newPtr;
	}

	/**
	 * GC facilities
	 */
	void addRoots(const void[] range) {
		auto ptr = cast(void*) roots.ptr;

		// We realloc everytime. It doesn't really matter at this point.
		roots.ptr = cast(const(void*)[]*)
			realloc(ptr, (roots.length + 1) * void*[].sizeof);

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
		import sdc.intrinsics;
		auto framePointer = readFramePointer();
		auto length = stackBottom - framePointer;

		auto range = makeRange(framePointer[0 .. length]);
		return scan(range);
	}

	bool scan(const(void*)[] range) {
		bool newPtr;
		foreach (ptr; range) {
			enum PtrMask = ~(AddressSpace - 1);
			auto iptr = cast(size_t) ptr;

			if (iptr & PtrMask) {
				// This is not a pointer, move along.
				// TODO: Replace this with a min-max test.
				continue;
			}

			auto pd = maybeGetPageDescriptor(ptr);
			if (pd.extent is null) {
				// We have no mappign there.
				continue;
			}

			// We have something, mark!
			newPtr |= true;

			// FIXME: Mark the extent.
			// FIXME: If the extent may contain pointers,
			// add the base ptr to the worklist.
		}

		return newPtr;
	}

private:
	auto getPageDescriptor(void* ptr) {
		auto pd = maybeGetPageDescriptor(ptr);
		assert(pd.extent !is null);
		assert(pd.isSlab() || ptr is pd.extent.addr);

		return pd;
	}

	auto maybeGetPageDescriptor(const void* ptr) {
		initializeExtentMap();

		import d.gc.util;
		auto aptr = alignDown(ptr, PageSize);
		return emap.lookup(aptr);
	}

	void initializeExtentMap() {
		import sdc.intrinsics;
		if (unlikely(emap is null)) {
			emap = gExtentMap;
		}
	}

	void initializeArena() {
		import sdc.intrinsics;
		if (likely(arena !is null)) {
			return;
		}

		initializeExtentMap();

		arena = &gArena;
		if (arena.regionAllocator is null) {
			import d.gc.region;
			arena.regionAllocator = gRegionAllocator;
		}
	}
}

private:

extern(C):
version(OSX) {
	// For some reason OSX's symbol get a _ prepended.
	bool _sdgc_push_registers(bool delegate());
	alias __sdgc_push_registers = _sdgc_push_registers;
} else {
	bool __sdgc_push_registers(bool delegate());
}

/**
 * This function get a void[] range and chnage it into a
 * const(void*)[] one, reducing to alignement boundaries.
 */
const(void*)[] makeRange(const void[] range) {
	auto begin = alignUp(range.ptr, PointerSize);
	auto end = alignDown(range.ptr + range.length, PointerSize);

	auto ibegin = cast(size_t) begin;
	auto iend = cast(size_t) end;
	if (ibegin > iend) {
		return [];
	}

	auto ptr = cast(void**) begin;
	auto length = (iend - ibegin) / PointerSize;

	return ptr[0 .. length];
}

unittest makeRange {
	static checkRange(const void[] range, size_t start, size_t stop) {
		auto r = makeRange(range);
		assert(r.ptr is cast(const void**) start);
		assert(r.ptr + r.length is cast(const void**) stop);
	}

	void* ptr;
	void[] range = ptr[0 .. 5];

	checkRange(ptr[0 .. 0], 0, 0);
	checkRange(ptr[0 .. 1], 0, 0);
	checkRange(ptr[0 .. 2], 0, 0);
	checkRange(ptr[0 .. 3], 0, 0);
	checkRange(ptr[0 .. 4], 0, 0);
	checkRange(ptr[0 .. 5], 0, 0);
	checkRange(ptr[0 .. 6], 0, 0);
	checkRange(ptr[0 .. 7], 0, 0);
	checkRange(ptr[0 .. 8], 0, 8);

	checkRange(ptr[1 .. 1], 0, 0);
	checkRange(ptr[1 .. 2], 0, 0);
	checkRange(ptr[1 .. 3], 0, 0);
	checkRange(ptr[1 .. 4], 0, 0);
	checkRange(ptr[1 .. 5], 0, 0);
	checkRange(ptr[1 .. 6], 0, 0);
	checkRange(ptr[1 .. 7], 0, 0);
	checkRange(ptr[1 .. 8], 8, 8);
}
