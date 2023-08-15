module d.gc.tcache;

import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

ThreadCache threadCache;

struct ThreadCache {
private:
	import d.gc.emap;
	shared(ExtentMap)* emap;

	const(void)* stackBottom;
	const(void*)[][] roots;

public:
	void* alloc(size_t size, bool containsPointers, bool isAppendable = false) {
		if (!isAllocatableSize(size)) {
			return null;
		}

		initializeExtentMap();

		auto arena = chooseArena(containsPointers);

		if (isAppendable) {
			// Currently, large (extent) allocs must be used for appendables:
			auto aSize = size;
			while (getAllocSize(aSize) <= SizeClass.Small) {
				aSize = getSizeFromClass(getSizeClass(aSize) + 1);
			}

			auto ptr = arena.allocLarge(emap, aSize, false);
			auto pd = getPageDescriptor(ptr);
			pd.extent.setAllocSize(size);
			return ptr;
		} else {
			return size <= SizeClass.Small
				? arena.allocSmall(emap, size)
				: arena.allocLarge(emap, size, false);
		}
	}

	void* calloc(size_t size, bool containsPointers) {
		if (!isAllocatableSize(size)) {
			return null;
		}

		initializeExtentMap();

		auto arena = chooseArena(containsPointers);
		if (size <= SizeClass.Small) {
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
		pd.arena.free(emap, pd, ptr);
	}

	// Determine whether given alloc is appendable
	bool is_appendable(void* ptr) {
		if (ptr is null)
			return false;

		auto pd = maybeGetPageDescriptor(ptr);
		if ((pd.extent is null) || (ptr !is pd.extent.address))
			return false;

		return pd.extent.isAppendable;
	}

	// Get the current fill of an appendable alloc.
	// If the alloc is not appendable, returns 0.
	ulong get_appendable_fill(void* ptr) {
		if (ptr is null)
			return 0;

		auto pd = maybeGetPageDescriptor(ptr);
		if ((pd.extent is null) || (ptr !is pd.extent.address))
			return 0;

		return pd.extent.allocSize;
	}

	// Get the current free space of an appendable alloc.
	// If the alloc is not appendable, returns 0.
	ulong get_appendable_free_space(void* ptr) {
		if (ptr is null)
			return 0;

		auto pd = maybeGetPageDescriptor(ptr);
		if ((pd.extent is null) || (ptr !is pd.extent.address)
			    || (!pd.extent.isAppendable))
			return 0;

		return cast(ulong) pd.extent.size - pd.extent.allocSize;
	}

	// Change the current fill of an appendable alloc.
	// If the alloc is not appendable, or the requested
	// fill exceeds the available space, returns false.
	bool set_appendable_fill(void* ptr, ulong fill) {
		if (ptr is null)
			return false;

		auto pd = maybeGetPageDescriptor(ptr);
		if ((pd.extent is null) || pd.isSlab() || (ptr !is pd.extent.address)
			    || (!pd.extent.isAppendable))
			return false;

		if (fill <= pd.extent.size) {
			pd.extent.setAllocSize(fill);
			return true;
		}

		return false;
	}

	void* realloc(void* ptr, size_t size, bool containsPointers) {
		if (!isAllocatableSize(size)) {
			free(ptr);
			return null;
		}

		if (ptr is null) {
			return alloc(size, containsPointers);
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
			copySize = min(size, esize);
		}

		containsPointers = (containsPointers | pd.containsPointers) != 0;
		auto newPtr = alloc(size, containsPointers);
		if (newPtr is null) {
			return null;
		}

		// TODO: transfer metadata

		memcpy(newPtr, ptr, copySize);
		pd.arena.free(emap, pd, ptr);

		return newPtr;
	}

	/**
	 * GC facilities
	 */
	void addRoots(const void[] range) {
		auto ptr = cast(void*) roots.ptr;

		// We realloc everytime. It doesn't really matter at this point.
		roots.ptr = cast(const(void*)[]*)
			realloc(ptr, (roots.length + 1) * void*[].sizeof, true);

		// Using .ptr to bypass bound checking.
		roots.ptr[roots.length] = makeRange(range);

		// Update the range.
		roots = roots.ptr[0 .. roots.length + 1];
	}

	void collect() {
		// TODO: The set need a range interface or some other way to iterrate.
		// FIXME: Prepare the GC so it has bitfields for all extent classes.

		// Scan the roots !
		__sd_gc_push_registers(scanStack);
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
		assert(pd.isSlab() || ptr is pd.extent.address);

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

	auto chooseArena(bool containsPointers) {
		/**
		 * We assume this call is cheap.
		 * This is true on modern linux with modern versions
		 * of glibc thanks to rseqs, but we might want to find
		 * an alternative on other systems.
		 */
		import sys.posix.sched;
		int cpuid = sched_getcpu();

		import d.gc.arena;
		return Arena.getOrInitialize((cpuid << 1) | containsPointers);
	}
}

private:

bool isAllocatableSize(size_t size) {
	return size > 0 && size <= MaxAllocationSize;
}

unittest isAllocatableSize {
	assert(!isAllocatableSize(0));
	assert(isAllocatableSize(1));
	assert(isAllocatableSize(42));
	assert(isAllocatableSize(99999));
	assert(isAllocatableSize(MaxAllocationSize));
	assert(!isAllocatableSize(MaxAllocationSize + 1));
	assert(!isAllocatableSize(size_t.max));
}

extern(C):
version(OSX) {
	// For some reason OSX's symbol get a _ prepended.
	bool _sd_gc_push_registers(bool delegate());
	alias __sd_gc_push_registers = _sd_gc_push_registers;
} else {
	bool __sd_gc_push_registers(bool delegate());
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

unittest appendableAlloc {
	auto p0 = threadCache.alloc(100, false, true);
	auto p1 = threadCache.alloc(100, false, false);
	assert(threadCache.is_appendable(p0));
	assert(!threadCache.is_appendable(p1));
	assert(threadCache.get_appendable_free_space(p1) == 0);
	assert(threadCache.get_appendable_fill(p0) == 100);
	assert(threadCache.get_appendable_free_space(p0) == 16284);
	assert(threadCache.set_appendable_fill(p0, 65536) == false);
	assert(threadCache.set_appendable_fill(p0, 200) == true);
	assert(threadCache.get_appendable_fill(p0) == 200);
	assert(threadCache.get_appendable_free_space(p0) == 16184);
	threadCache.free(p0);
}
