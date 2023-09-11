module d.gc.tcache;

import d.gc.size;
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
	void* alloc(size_t size, bool containsPointers) {
		if (!isAllocatableSize(size)) {
			return null;
		}

		initializeExtentMap();

		auto arena = chooseArena(containsPointers);
		return isSmallSize(size)
			? arena.allocSmall(emap, size)
			: arena.allocLarge(emap, size, false);
	}

	void* allocAppendable(size_t size, bool containsPointers) {
		// Force large allocation rather than slab.
		enum MinSize = getSizeFromClass(ClassCount.Small);

		import d.gc.util;
		auto asize = max(MinSize, getAllocSize(size));
		auto ptr = alloc(asize, containsPointers);

		// Remember the size we actually use.
		auto pd = getPageDescriptor(ptr);
		pd.extent.setUsedCapacity(size);
		return ptr;
	}

	void* calloc(size_t size, bool containsPointers) {
		if (!isAllocatableSize(size)) {
			return null;
		}

		initializeExtentMap();

		auto arena = chooseArena(containsPointers);
		if (isLargeSize(size)) {
			return arena.allocLarge(emap, size, true);
		}

		auto ret = arena.allocSmall(emap, size);
		memset(ret, 0, size);
		return ret;
	}

	void free(void* ptr) {
		if (ptr is null) {
			return;
		}

		auto pd = getPageDescriptor(ptr);
		pd.arena.free(emap, pd, ptr);
	}

	void* realloc(void* ptr, size_t size, bool containsPointers) {
		if (size == 0) {
			free(ptr);
			return null;
		}

		if (!isAllocatableSize(size)) {
			return null;
		}

		if (ptr is null) {
			return alloc(size, containsPointers);
		}

		auto copySize = size;
		auto pd = getPageDescriptor(ptr);
		auto samePointerness = containsPointers == pd.containsPointers;

		if (pd.isSlab()) {
			auto newSizeClass = getSizeClass(size);
			auto oldSizeClass = pd.sizeClass;
			if (samePointerness && newSizeClass == oldSizeClass) {
				return ptr;
			}

			if (newSizeClass > oldSizeClass) {
				copySize = getSizeFromClass(oldSizeClass);
			}
		} else {
			auto esize = pd.extent.size;
			if (samePointerness && (alignUp(size, PageSize) == esize
				    || (isLargeSize(size)
					    && pd.arena.resizeLarge(emap, pd.extent, size)))) {
				pd.extent.setUsedCapacity(size);
				return ptr;
			}

			import d.gc.util;
			copySize = min(size, pd.extent.usedCapacity);
		}

		auto newPtr = alloc(size, containsPointers);
		if (newPtr is null) {
			return null;
		}

		if (isLargeSize(size)) {
			auto npd = getPageDescriptor(newPtr);
			npd.extent.setUsedCapacity(size);
		}

		memcpy(newPtr, ptr, copySize);
		pd.arena.free(emap, pd, ptr);

		return newPtr;
	}

	/**
	 * Appendable facilities.
	 */

	/**
	 * Appendable's mechanics:
	 * 
	 *  __data__  _____free space_______
	 * /        \/                      \
	 * -----sss s....... ....... ........
	 *      \___________________________/
	 * 	           Capacity is 27
	 * 
	 * If the slice's end doesn't match the used capacity,
	 * then we return 0 in order to force a reallocation
	 * when appending:
	 * 
	 *  ___data____  ____free space_____
	 * /           \/                   \
	 * -----sss s---.... ....... ........
	 *      \___________________________/
	 * 	           Capacity is 0
	 * 
	 * See also: https://dlang.org/spec/arrays.html#capacity-reserve
	 */
	bool getAppendablePageDescriptor(const void[] slice,
	                                 ref PageDescriptor pd) {
		pd = maybeGetPageDescriptor(slice.ptr);
		if (pd.extent is null) {
			return false;
		}

		// Appendable slabs are not supported.
		if (pd.isSlab()) {
			return false;
		}

		// Slice must not end before valid data ends, or capacity is zero:
		auto startIndex = slice.ptr - pd.extent.address;
		auto stopIndex = startIndex + slice.length;

		// If the slice end doesn't match the used capacity, not appendable.
		return stopIndex == pd.extent.usedCapacity;
	}

	size_t getCapacity(const void[] slice) {
		PageDescriptor pd;
		if (!getAppendablePageDescriptor(slice, pd)) {
			return 0;
		}

		auto startIndex = slice.ptr - pd.extent.address;
		return pd.extent.size - startIndex;
	}

	bool extend(const void[] slice, size_t size) {
		if (size == 0) {
			return true;
		}

		PageDescriptor pd;
		if (!getAppendablePageDescriptor(slice, pd)) {
			return false;
		}

		// There must be sufficient free space to extend into:
		auto newCapacity = pd.extent.usedCapacity + size;
		if (pd.extent.size < newCapacity) {
			return false;
		}

		// Increase the used capacity by the requested size:
		pd.extent.setUsedCapacity(newCapacity);

		return true;
	}

	/**
	 * GC facilities.
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

/**
 * Packed Free Space is stored as a 15-bit unsigned integer, in one or two bytes:
 *
 * /---- byte at ptr ----\ /-- byte at ptr + 1 --\
 * B7 B6 B5 B4 B3 B2 B1 B0 A7 A6 A5 A4 A3 A2 A1 A0
 * \_________15 bits unsigned integer_________/  \_ Set if and only if B0..B7 used.
 */

ushort readPackedFreeSpace(ushort* ptr) {
	auto data = loadBigEndian(ptr);
	auto mask = 0x7f | -(data & 1);
	return (data >> 1) & mask;
}

void writePackedFreeSpace(ushort* ptr, ushort x) {
	assert(x < 0x8000, "x does not fit in 15 bits!");

	auto base = cast(ushort) ((x << 1) | (x > 0x7f));
	auto mask = (0 - (x > 0x7f)) | 0xff;

	auto current = loadBigEndian(ptr);
	auto delta = (current ^ base) & mask;
	auto value = current ^ delta;

	storeBigEndian(ptr, cast(ushort) (value & ushort.max));
}

unittest PackedFreeSpace {
	ubyte[2] a;
	foreach (ushort i; 0 .. 0x8000) {
		auto p = cast(ushort*) a.ptr;
		writePackedFreeSpace(p, i);
		assert(readPackedFreeSpace(p) == i);
	}

	foreach (x; 0 .. 256) {
		a[0] = 0xff & x;
		foreach (ubyte y; 0 .. 0x80) {
			auto p = cast(ushort*) a.ptr;
			writePackedFreeSpace(p, y);
			assert(readPackedFreeSpace(p) == y);
			assert(a[0] == x);
		}
	}
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

unittest getCapacity {
	// Test capacity for non appendable allocs.
	auto nonAppendable = threadCache.alloc(100, false);
	assert(threadCache.getCapacity(nonAppendable[0 .. 100]) == 0);

	// Capacity of any slice in space unknown to the GC is zero:
	void* nullPtr = null;
	assert(threadCache.getCapacity(nullPtr[0 .. 100]) == 0);

	void* stackPtr = &nullPtr;
	assert(threadCache.getCapacity(stackPtr[0 .. 100]) == 0);

	void* tlPtr = &threadCache;
	assert(threadCache.getCapacity(tlPtr[0 .. 100]) == 0);

	// Check capacity for an appendable GC allocation.
	auto p0 = threadCache.allocAppendable(100, false);

	// p0 is appendable and has the minimum large size.
	// Capacity of segment from p0, length 100 is 16384:
	assert(threadCache.getCapacity(p0[0 .. 100]) == 16384);
	assert(threadCache.getCapacity(p0[1 .. 100]) == 16383);
	assert(threadCache.getCapacity(p0[50 .. 100]) == 16334);
	assert(threadCache.getCapacity(p0[99 .. 100]) == 16285);
	assert(threadCache.getCapacity(p0[100 .. 100]) == 16284);

	// If the slice doesn't go the end of the allocated area
	// then the capacity must be 0.
	assert(threadCache.getCapacity(p0[0 .. 0]) == 0);
	assert(threadCache.getCapacity(p0[0 .. 1]) == 0);
	assert(threadCache.getCapacity(p0[0 .. 50]) == 0);
	assert(threadCache.getCapacity(p0[0 .. 99]) == 0);

	assert(threadCache.getCapacity(p0[0 .. 99]) == 0);
	assert(threadCache.getCapacity(p0[1 .. 99]) == 0);
	assert(threadCache.getCapacity(p0[50 .. 99]) == 0);
	assert(threadCache.getCapacity(p0[99 .. 99]) == 0);

	// This would almost certainly be a bug in userland,
	// but let's make sure be behave reasonably there.
	assert(threadCache.getCapacity(p0[0 .. 101]) == 0);
	assert(threadCache.getCapacity(p0[1 .. 101]) == 0);
	assert(threadCache.getCapacity(p0[50 .. 101]) == 0);
	assert(threadCache.getCapacity(p0[100 .. 101]) == 0);
	assert(threadCache.getCapacity(p0[101 .. 101]) == 0);

	// Realloc.
	auto p1 = threadCache.allocAppendable(20000, false);
	assert(threadCache.getCapacity(p1[0 .. 19999]) == 0);
	assert(threadCache.getCapacity(p1[0 .. 20000]) == 20480);
	assert(threadCache.getCapacity(p1[0 .. 20001]) == 0);

	// Decreasing the size of the allocation
	// should adjust capacity acordingly.
	auto p2 = threadCache.realloc(p1, 19999, false);
	assert(p2 is p1);

	assert(threadCache.getCapacity(p2[0 .. 19999]) == 20480);
	assert(threadCache.getCapacity(p2[0 .. 20000]) == 0);
	assert(threadCache.getCapacity(p2[0 .. 20001]) == 0);

	// Increasing the size of the allocation increases capacity.
	auto p3 = threadCache.realloc(p2, 20001, false);
	assert(p3 is p2);

	assert(threadCache.getCapacity(p3[0 .. 19999]) == 0);
	assert(threadCache.getCapacity(p3[0 .. 20000]) == 0);
	assert(threadCache.getCapacity(p3[0 .. 20001]) == 20480);

	// This realloc happens in-place:
	auto p4 = threadCache.realloc(p3, 16000, false);
	assert(p4 is p3);
	assert(threadCache.getCapacity(p4[0 .. 16000]) == 16384);

	// This one, not:
	auto p5 = threadCache.realloc(p4, 20000, false);
	assert(p5 !is p4);
	assert(threadCache.getCapacity(p5[0 .. 20000]) == 20480);

	// Realloc from large to small size class results in new allocation:
	auto p6 = threadCache.realloc(p5, 100, false);
	assert(p6 !is p5);
}

unittest extend {
	auto nonAppendable = threadCache.alloc(100, false);

	// Attempt to extend a non-appendable:
	assert(!threadCache.extend(nonAppendable[0 .. 100], 1));

	// Extend by zero is permitted even when no capacity:
	assert(threadCache.extend(nonAppendable[0 .. 100], 0));

	// Extend in space unknown to the GC. Can only extend by zero.
	void* nullPtr = null;
	assert(threadCache.extend(nullPtr[0 .. 100], 0));
	assert(!threadCache.extend(nullPtr[0 .. 100], 1));
	assert(!threadCache.extend(nullPtr[100 .. 100], 1));

	void* stackPtr = &nullPtr;
	assert(threadCache.extend(stackPtr[0 .. 100], 0));
	assert(!threadCache.extend(stackPtr[0 .. 100], 1));
	assert(!threadCache.extend(stackPtr[100 .. 100], 1));

	void* tlPtr = &threadCache;
	assert(threadCache.extend(tlPtr[0 .. 100], 0));
	assert(!threadCache.extend(tlPtr[0 .. 100], 1));
	assert(!threadCache.extend(tlPtr[100 .. 100], 1));

	// Make an appendable alloc:
	auto p0 = threadCache.allocAppendable(100, false);
	assert(threadCache.getCapacity(p0[0 .. 100]) == 16384);

	// Attempt to extend valid slices with capacity 0.
	// (See getCapacity tests.)
	assert(threadCache.extend(p0[0 .. 0], 0));
	assert(!threadCache.extend(p0[0 .. 0], 50));
	assert(!threadCache.extend(p0[0 .. 99], 50));
	assert(!threadCache.extend(p0[1 .. 99], 50));
	assert(!threadCache.extend(p0[0 .. 50], 50));

	// Extend by size zero is permitted but has no effect:
	assert(threadCache.extend(p0[100 .. 100], 0));
	assert(threadCache.extend(p0[0 .. 100], 0));
	assert(threadCache.getCapacity(p0[0 .. 100]) == 16384);
	assert(threadCache.extend(p0[50 .. 100], 0));
	assert(threadCache.getCapacity(p0[50 .. 100]) == 16334);

	// Attempt extend with insufficient space (one byte too many) :
	assert(threadCache.getCapacity(p0[100 .. 100]) == 16284);
	assert(!threadCache.extend(p0[0 .. 100], 16285));
	assert(!threadCache.extend(p0[50 .. 100], 16285));

	// Extending to the limit (one less than above) succeeds:
	assert(threadCache.extend(p0[50 .. 100], 16284));

	// Now we're full, and can extend only by zero:
	assert(threadCache.extend(p0[0 .. 16384], 0));
	assert(!threadCache.extend(p0[0 .. 16384], 1));

	// Make another appendable alloc:
	auto p1 = threadCache.allocAppendable(100, false);
	assert(threadCache.getCapacity(p1[0 .. 100]) == 16384);

	// Valid extend :
	assert(threadCache.extend(p1[0 .. 100], 50));
	assert(threadCache.getCapacity(p1[100 .. 150]) == 16284);
	assert(threadCache.extend(p1[0 .. 150], 0));

	// Capacity of old slice becomes 0:
	assert(threadCache.getCapacity(p1[0 .. 100]) == 0);

	// The only permitted extend is by 0:
	assert(threadCache.extend(p1[0 .. 100], 0));

	// Capacity of a slice including the original and the extension:
	assert(threadCache.getCapacity(p1[0 .. 150]) == 16384);

	// Extend the upper half:
	assert(threadCache.extend(p1[125 .. 150], 100));
	assert(threadCache.getCapacity(p1[150 .. 250]) == 16234);

	// Original's capacity becomes 0:
	assert(threadCache.getCapacity(p1[125 .. 150]) == 0);
	assert(threadCache.extend(p1[125 .. 150], 0));

	// Capacity of a slice including original and extended:
	assert(threadCache.extend(p1[125 .. 250], 0));
	assert(threadCache.getCapacity(p1[125 .. 250]) == 16259);

	// Capacity of earlier slice elongated to cover the extensions :
	assert(threadCache.getCapacity(p1[0 .. 250]) == 16384);

	// Extend a zero-size slice existing at the start of the free space:
	assert(threadCache.extend(p1[250 .. 250], 200));
	assert(threadCache.getCapacity(p1[250 .. 450]) == 16134);

	// Capacity of the old slice is now 0:
	assert(threadCache.getCapacity(p1[0 .. 250]) == 0);

	// Capacity of a slice which includes the original and the extension:
	assert(threadCache.getCapacity(p1[0 .. 450]) == 16384);

	// Extend so as to fill up all but one byte of free space:
	assert(threadCache.extend(p1[0 .. 450], 15933));
	assert(threadCache.getCapacity(p1[16383 .. 16383]) == 1);

	// Extend, filling up last byte of free space:
	assert(threadCache.extend(p1[16383 .. 16383], 1));
	assert(threadCache.getCapacity(p1[0 .. 16384]) == 16384);

	// Attempt to extend, but we're full:
	assert(!threadCache.extend(p1[0 .. 16384], 1));

	// Extend by size zero still works, though:
	assert(threadCache.extend(p1[0 .. 16384], 0));
}
