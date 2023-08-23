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
			// Currently, large (extent) allocs are appendable.
			auto aSize = upsizeToLarge(size);
			auto ptr = arena.allocLarge(emap, aSize, false);
			setAllocSize(ptr, size);
			return ptr;
		} else {
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

	void* realloc(void* ptr, size_t size, bool containsPointers) {
		if (!isAllocatableSize(size)) {
			free(ptr);
			return null;
		}

		if (ptr is null) {
			return alloc(size, containsPointers);
		}

		auto copySize = size;
		auto newSize = size;
		auto pd = getPageDescriptor(ptr);
		// Whether old (and therefore new) block is appendable:
		bool appendable = false;

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
			appendable = true;
			auto esize = pd.extent.size;
			if (alignUp(size, PageSize) == esize) {
				return ptr;
			}

			// TODO: Try to extend/shrink in place.
			copySize = min(min(size, esize), pd.extent.allocSize);
			if (size > esize) {
				newSize = upsizeOneClass(size);
			}
		}

		containsPointers = (containsPointers | pd.containsPointers) != 0;
		auto newPtr = alloc(newSize, containsPointers, appendable);
		if (newPtr is null) {
			return null;
		}

		if (appendable)
			setAllocSize(newPtr, copySize);

		memcpy(newPtr, ptr, copySize);
		pd.arena.free(emap, pd, ptr);

		return newPtr;
	}

	/**
	 * Appendables API.
	 */

	// Mechanics of Appendable Capacity:
	//
	//   ______data_____  ___free space___
	//  /               \/                \
	// |X|X|X|X|X|S|S|S|S|.|.|.|.|.|.|.|.|.|
	//           \________________________/
	// 	       Capacity of segment S is 13
	//
	// Similarly:
	// |X|X|X|X|X|S|S|S|S|S|S|S|S|S|S|S|S|S|
	//
	// No free space next to S, so capacity(S) is 0:
	// |S|S|S|S|X|X|X|X|X|.|.|.|.|.|.|.|.|.|
	//
	// Similarly:
	// |X|X|X|X|S|S|S|S|X|.|.|.|.|.|.|.|.|.|

	// Get the appendable capacity of a given segment:
	// i.e. the max length that segment can grow to without a reallocation.
	// Segments without free space immediately above them have capacity of 0.
	// Note that a segment of length 0 at the start of free space can have
	// a capacity > 0 (i.e. equal to the length of the free space.)
	// See also: https://dlang.org/spec/arrays.html#capacity-reserve
	size_t getCapacity(const void[] segment) {
		auto pd = maybeGetPageDescriptor(segment.ptr);
		// Return zero if ptr unknown to GC or points to non-appendable block:
		if ((pd.extent is null) || (!pd.extent.isAppendable()))
			return 0;

		// Position of segment start in the block with respect to the bottom :
		auto segStart = segment.ptr - pd.extent.address;

		// Segment end must match end of valid data, or capacity is zero:
		if (segStart + segment.length != pd.extent.allocSize)
			return 0;

		// Otherwise, return length of segment plus any free space above it:
		return pd.extent.size - segStart;
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
	void setAllocSize(void* ptr, size_t size) {
		auto pd = getPageDescriptor(ptr);
		pd.extent.setAllocSize(size);
	}

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

// Get the size of the size class above the one size would normally be in.
size_t upsizeOneClass(size_t size) {
	return getSizeFromClass(getSizeClass(size) + 1);
}

// Force large allocation rather than slab
size_t upsizeToLarge(size_t size) {
	return isLargeSize(size) ? size : getAllocSize(SizeClass.Small + 1);
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
	assert(threadCache.getCapacity(p1[0 .. 100]) == 0);
	threadCache.free(p1);

	// p0 is appendable and has the minimum large size.
	// Capacity of segment from p0, length 100 is 16384:
	assert(threadCache.getCapacity(p0[0 .. 100]) == 16384);

	// Capacity of segment p0 + 50, length 50, is less by 50:
	assert(threadCache.getCapacity(p0[50 .. 100]) == 16334);

	// Segment includes all but one byte of the data:
	assert(threadCache.getCapacity(p0[1 .. 100]) == 16383);

	// Segment of length 0 at the start of the free space:
	assert(threadCache.getCapacity(p0[100 .. 100]) == 16284);

	// Capacity of segment p0 + 50, length 49, is zero, as
	// its end does not match the end of the valid data:
	assert(threadCache.getCapacity(p0[50 .. 99]) == 0);

	// A byte short of the data end, capacity is zero:
	assert(threadCache.getCapacity(p0[0 .. 99]) == 0);

	// Similarly, segment end does not match valid data end,
	// so capacity will be 0:
	assert(threadCache.getCapacity(p0[0 .. 99]) == 0);

	// Zero-length segment of alloc where data exists in front of it:
	assert(threadCache.getCapacity(p0[0 .. 0]) == 0);

	// Out-of-bounds segment has capacity of 0:
	assert(threadCache.getCapacity(p0[0 .. 101]) == 0);

	// D's dynamic arrays are permitted to start empty
	// with a spare capacity.

	// TODO: rewrite realloc() tests
}
