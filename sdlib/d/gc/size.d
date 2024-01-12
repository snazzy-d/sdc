module d.gc.size;

import d.gc.sizeclass;
import d.gc.spec;

// We make sure we can count allocated pages on a uint.
enum MaxAllocationSize = uint.max * PageSize;

// Determine whether given size is permitted by allocator.
bool isAllocatableSize(size_t size) {
	return size > 0 && size <= MaxAllocationSize;
}

unittest isAllocatableSize {
	assert(!isAllocatableSize(0));
	assert(isAllocatableSize(1));
	assert(isAllocatableSize(42));
	assert(isAllocatableSize(99999));
	assert(isAllocatableSize(uint.max));
	assert(isAllocatableSize(MaxAllocationSize));
	assert(!isAllocatableSize(MaxAllocationSize + 1));
	assert(!isAllocatableSize(size_t.max));
}

enum MaxSmallSize = getSizeFromClass(ClassCount.Small - 1);
enum MaxLargeSize = getSizeFromClass(ClassCount.Large - 1);

enum MaxPagesInLargeAlloc = getPageCount(MaxLargeSize);

// Determine whether given size may fit into a 'small' (slab-allocatable) size class.
bool isSmallSize(size_t size) {
	return (size > 0) && (size <= MaxSmallSize);
}

// Determine whether given size may fit into a 'large' size class.
bool isLargeSize(size_t size) {
	import d.gc.size;
	return (size > MaxSmallSize) && (size <= MaxLargeSize);
}

bool isHugeSize(size_t size) {
	import d.gc.size;
	return (size > MaxLargeSize) && (size <= MaxAllocationSize);
}

unittest sizePredicates {
	assert(MaxSmallSize == 14336, "Unexpected max small size!");
	assert(MaxLargeSize == 1835008, "Unexpected max large size!");

	assert(!isSmallSize(0));
	assert(!isLargeSize(0));
	assert(!isHugeSize(0));

	void checkSmall(size_t size) {
		assert(isSmallSize(size));
		assert(!isLargeSize(size));
		assert(!isHugeSize(size));

		auto sc = getSizeClass(size);
		assert(isSmallSizeClass(sc));
		assert(!isLargeSizeClass(sc));
		assert(!isHugeSizeClass(sc));
	}

	void checkLarge(size_t size) {
		assert(!isSmallSize(size));
		assert(isLargeSize(size));
		assert(!isHugeSize(size));

		auto sc = getSizeClass(size);
		assert(!isSmallSizeClass(sc));
		assert(isLargeSizeClass(sc));
		assert(!isHugeSizeClass(sc));
	}

	void checkHuge(size_t size) {
		assert(!isSmallSize(size));
		assert(!isLargeSize(size));
		assert(isHugeSize(size));

		auto sc = getSizeClass(size);
		assert(!isSmallSizeClass(sc));
		assert(!isLargeSizeClass(sc));
		assert(isHugeSizeClass(sc));
	}

	foreach (s; 1 .. MaxSmallSize) {
		checkSmall(s);
	}

	// MaxSmallSize is the largest small size.
	checkSmall(MaxSmallSize);

	// MaxSmallSize + 1 is no longer small.
	checkLarge(MaxSmallSize + 1);

	// MaxLargeSize is the largest large size.
	checkLarge(MaxLargeSize);

	// MaxLargeSize + 1 is no longer large.
	checkHuge(MaxLargeSize + 1);

	// MaxAllocationSize is obviously huge.
	import d.gc.size;
	checkHuge(MaxAllocationSize);
}

uint getPageCount(size_t size) {
	assert(isAllocatableSize(size), "Invalid size!");

	import d.gc.util;
	auto pages = alignUp(size, PageSize) / PageSize;
	assert(pages == pages & uint.max, "Invalid page count!");

	return pages & uint.max;
}
