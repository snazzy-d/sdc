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
	void* alloc(size_t size, bool containsPointers, bool isAppendable = false) {
		if (!isAllocatableSize(size)) {
			return null;
		}

		initializeExtentMap();

		auto arena = chooseArena(containsPointers);

		if (isAppendable) {
			// Currently, large (extent) allocs must be used for appendables:
			auto ptr = arena.allocLarge(emap, upsizeToLarge(size), false);
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

	// Get the capacity of the array slice denoted by slice and length.
	size_t getArrayCapacity(void* sliceAddr, size_t sliceLen) {
		if ((sliceAddr is null) || (!sliceLen))
			return 0;

		auto pd = maybeGetPageDescriptor(sliceAddr);
		// Return zero if slice is unknown to GC or is to a non-appendable block:
		if ((pd.extent is null) || (!pd.extent.allocSize))
			return 0;

		// Capacity is defined as zero if an element exists after the slice.
		// See also: https://dlang.org/spec/arrays.html#capacity-reserve
		if (sliceAddr - pd.extent.address + sliceLen < pd.extent.allocSize)
			return 0;

		// Otherwise, capacity is the block size minus the slice length:
		return pd.extent.size - sliceLen;
	}

	// Append array slice denoted by rAddr and rBytes to the one
	// denoted by lAddr and lBytes, using the former's appendable capacity
	// if possible, otherwise allocating a new array.
	void* appendArray(void* lAddr, size_t lBytes, void* rAddr, size_t rBytes) {
		// If right slice is of zero length, return left slice unchanged:
		if (!rBytes)
			return lAddr;

		// Whether we will be appending in place, or must realloc:
		bool inPlace = getArrayCapacity(lAddr, lBytes) >= rBytes;

		// If appending in place, use lAddr for result:
		void* appended = lAddr;

		auto pdLeft = maybeGetPageDescriptor(lAddr);

		if (inPlace) {
			// Knowing that left slice is appendable, set its block's fill:
			assert(pdLeft.extent.isLarge());
			pdLeft.extent.setAllocSize(lBytes + rBytes);
		} else {
			// If either left or right slice is know to GC and contains pointers,
			// the result will therefore also contain pointers:
			auto pdRight = maybeGetPageDescriptor(rAddr);
			bool hasPointers = ((pdLeft.extent !is null)
					&& (pdLeft.containsPointers))
				|| ((pdRight.extent !is null) && (pdRight.containsPointers));
			// Allocate a new appendable block:
			appended = alloc(lBytes + rBytes, hasPointers, true);
			// OOM?
			if (appended is null)
				return null;
			// Copy the left slice:
			memcpy(appended, lAddr, lBytes);
		}

		// In either case, copy right slice to the space after left slice:
		memcpy(appended + lBytes, rAddr, rBytes);

		// Return the appended block:
		return appended;
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

		size_t oldFill = 0;
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
			oldFill = pd.extent.allocSize;

			// Prohibit resize below appendable fill:
			if (size < oldFill)
				return ptr;

			auto oldSize = oldFill ? oldFill : pd.extent.size;

			if (alignUp(size, PageSize) == alignUp(oldSize, PageSize)) {
				return ptr;
			}

			// TODO: Try to extend/shrink in place.
			copySize = min(size, oldSize);
		}

		containsPointers = (containsPointers | pd.containsPointers) != 0;
		auto useSize = oldFill ? upsizeToLarge(size) : size;
		auto newPtr = alloc(useSize, containsPointers);
		if (newPtr is null) {
			return null;
		}

		memcpy(newPtr, ptr, copySize);

		if (oldFill) {
			auto pdNew = getPageDescriptor(newPtr);
			assert(pdNew.extent.isLarge());
			pdNew.extent.setAllocSize(oldFill);
		}

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
	int[] a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
	int[] b = [11, 12, 13];
	int[] c = [14, 15, 16];

	assert(!threadCache.getArrayCapacity(a.ptr, a.length * int.sizeof));
	assert(!threadCache.getArrayCapacity(b.ptr, b.length * int.sizeof));
	assert(!threadCache.getArrayCapacity(c.ptr, c.length * int.sizeof));

	// a ~= b :
	auto _ab = threadCache.appendArray(a.ptr, int.sizeof * a.length, b.ptr,
	                                   int.sizeof * b.length);
	assert(_ab !is null);
	assert(_ab !is cast(void*) a.ptr);
	int[] ab = cast(int[]) _ab[0 .. a.length + b.length];

	assert(threadCache.getArrayCapacity(ab.ptr, int.sizeof * ab.length));
	assert(ab[12] == 13);

	// ab ~= c :
	auto _abc = threadCache.appendArray(ab.ptr, int.sizeof * ab.length, c.ptr,
	                                    int.sizeof * c.length);
	int[] abc = cast(int[]) _abc[0 .. ab.length + c.length];
	assert(abc[15] == 16);
	// Must have appended in-place:
	assert(_abc is _ab);
}
