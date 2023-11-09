module d.gc.size;

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

uint getPageCount(size_t size) {
	assert(isAllocatableSize(size), "Invalid size!");

	import d.gc.util;
	auto pages = alignUp(size, PageSize) / PageSize;
	assert(pages == pages & uint.max, "Invalid page count!");

	return pages & uint.max;
}

uint getBlockCount(size_t size) {
	assert(isAllocatableSize(size), "Invalid size!");

	import d.gc.util;
	auto pages = alignUp(size, BlockSize) / BlockSize;
	assert(pages == pages & uint.max, "Invalid block count!");

	return pages & uint.max;
}
