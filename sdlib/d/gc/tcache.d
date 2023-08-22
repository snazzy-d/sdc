module d.gc.tcache;

import d.gc.extent;
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
	void* alloc(size_t size, bool containsPointers, bool isAppendable = false,
	            size_t spareCapacity = 0) {
		// spareCapacity is ignored if alloc is not appendable.

		initializeExtentMap();

		auto arena = chooseArena(containsPointers);

		if (isAppendable) {
			auto reqSize = size + spareCapacity;
			if (!isAllocatableSize(reqSize))
				return null;

			// Currently, large (extent) allocs must be used for appendables.
			auto ptr = arena.allocLarge(emap, upsizeToLarge(reqSize), false);
			auto pd = getPageDescriptor(ptr);
			// Size (which may be 0 if spareCapacity > 0) becomes the fill.
			pd.extent.setAllocSize(size);
			return ptr;
		} else {
			if (!isAllocatableSize(size))
				return null;

			return isSmallSize(size)
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
		if (isSmallSize(size)) {
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

	/**
	 * Appendables API.
	 */

	// Get the append capacity of a segment denoted by ptr and len,
	// i.e. the max length that segment can grow to without a reallocation.
	// See also: https://dlang.org/spec/arrays.html#capacity-reserve
	size_t getCapacity(void* ptr, size_t len) {
		auto pd = maybeGetPageDescriptor(ptr);
		// Return zero if ptr unknown to GC or points to non-appendable block:
		if ((pd.extent is null) || (!pd.extent.isAppendable()))
			return 0;

		// Position of segment start in the block with respect to the bottom :
		auto segStart = ptr - pd.extent.address;
		// Position of segment end :
		auto segEnd = segStart + len;

		assert(segEnd <= pd.extent.allocSize, "Segment end is out of range!");

		// Segment must not end before valid data ends, or capacity is zero:
		if (segEnd < pd.extent.allocSize)
			return 0;

		// Otherwise, return length of segment and the free space above it:
		return pd.extent.size - segStart;
	}

	/**
	 * Reallocation.
	 */

	void* realloc(void* ptr, size_t size, bool containsPointers) {
		if (!isAllocatableSize(size)) {
			free(ptr);
			return null;
		}

		if (ptr is null) {
			return alloc(size, containsPointers);
		}

		// Whether old (and therefore new) block is appendable:
		bool appendable = false;
		// Spare capacity for enlarging appendable block:
		size_t spareCapacity = 0;
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
			// New block will be appendable if the old one was:
			appendable = pd.extent.isAppendable();

			// Prohibit resize below appendable fill, if one exists:
			if (appendable && (size < pd.extent.allocSize))
				return ptr;

			auto esize = pd.extent.size;
			if (alignUp(size, PageSize) == esize) {
				return ptr;
			}

			// TODO: Try to extend/shrink in place.
			if (appendable) {
				copySize = pd.extent.allocSize;
				// If enlarging an appendable, boost spare capacity:
				if (esize < size)
					spareCapacity = esize * 2;
			} else {
				copySize = min(size, esize);
			}
		}

		containsPointers = (containsPointers | pd.containsPointers) != 0;
		auto useSize = appendable ? copySize : size;
		auto newPtr =
			alloc(useSize, containsPointers, appendable, spareCapacity);
		if (newPtr is null) {
			return null;
		}

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

// Force large allocation rather than slab
size_t upsizeToLarge(size_t size) {
	return getAllocSize(size) <= SizeClass.Small ? SizeClass.Large : size;
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
	// Basics:
	auto p0 = threadCache.alloc(100, false, true);
	auto p1 = threadCache.alloc(100, false, false);

	// p1 is not appendable:
	assert(threadCache.getCapacity(p1, 100) == 0);
	threadCache.free(p1);

	// p0 is appendable and has the minimum large size.
	// Capacity of segment from p0, length 100 is 16384:
	assert(threadCache.getCapacity(p0, 100) == 16384);

	// Capacity of segment p0 + 50, length 50, is less by 50:
	assert(threadCache.getCapacity(p0 + 50, 50) == 16334);

	// Segment includes all but one byte of the data:
	assert(threadCache.getCapacity(p0 + 1, 99) == 16383);

	// Capacity of segment p0 + 50, length 49, is zero, as
	// its end does not match the end of the valid data:
	assert(threadCache.getCapacity(p0 + 50, 49) == 0);

	// A byte short of the data end, capacity is zero:
	assert(threadCache.getCapacity(p0 + 1, 98) == 0);

	// Similarly, segment end does not match valid data end,
	// so capacity will be 0:
	assert(threadCache.getCapacity(p0, 99) == 0);

	// Zero-length segment of alloc where data exists in front of it:
	assert(threadCache.getCapacity(p0, 0) == 0);

	// D's dynamic arrays are permitted to start empty
	// with a spare capacity.

	// An 'empty' appendable with spare capacity:
	auto p2 = threadCache.alloc(0, false, true, 100);

	// Zero-length segment then has full capacity of the free space:
	assert(threadCache.getCapacity(p2, 0) == 16384);

	// Realloc.

	// This realloc will have no effect, as the requested size
	// is below the appendable fill size:
	auto p3 = threadCache.realloc(p0, 99, false);
	assert(p3 == p0);

	// Enlarging the spare capacity :
	p0 = threadCache.realloc(p0, 16385, false);
	assert(threadCache.getCapacity(p0, 100) == 36864);

	// Reduce again to minimum:
	p0 = threadCache.realloc(p0, 100, false);
	assert(threadCache.getCapacity(p0, 100) == 16384);

	// Enlarge the empty (will double in total capacity) :
	p2 = threadCache.realloc(p2, 16385, false);
	assert(threadCache.getCapacity(p2, 0) == 32768);

	threadCache.free(p0);
	threadCache.free(p2);

	// Capacity of any segment in space unknown to the GC is zero:
	int[] a = [1, 2, 3];
	assert(threadCache.getCapacity(a.ptr, int.sizeof * a.length) == 0);
}
