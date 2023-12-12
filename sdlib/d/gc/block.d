module d.gc.block;

import d.gc.base;
import d.gc.heap;
import d.gc.spec;
import d.gc.util;

/**
 * Each BlockDescriptor manages a 2MB system's huge page.
 *
 * In order to reduce TLB pressure, we try to layout the memory in
 * such a way that the OS can back it with huge pages. We organise
 * the memory in blocks that correspond to a huge page, and allocate
 * in blocks that are unlikely to empty themselves any time soon.
 */
struct BlockDescriptor {
private:
	void* address;
	ulong epoch;

	import d.gc.heap;
	Node!BlockDescriptor phnode;

	uint longestFreeRange = PagesInBlock;

	uint usedCount;
	uint dirtyCount;
	ubyte generation;

	import d.gc.bitmap;
	Bitmap!PagesInBlock allocatedPages;
	Bitmap!PagesInBlock dirtyPages;

	this(void* address, ulong epoch, ubyte generation = 0) {
		this.address = address;
		this.epoch = epoch;
		this.generation = generation;
	}

public:
	BlockDescriptor* at(void* ptr, ulong epoch) {
		this = BlockDescriptor(ptr, epoch, generation);
		return &this;
	}

	static fromPage(GenerationPointer page) {
		// FIXME: in contract
		assert(page.address !is null, "Invalid page!");
		assert(isAligned(page.address, PageSize), "Invalid page!");

		enum BlockDescriptorSize = alignUp(BlockDescriptor.sizeof, CacheLine);
		enum Count = PageSize / BlockDescriptorSize;
		static assert(Count == 21, "Unexpected BlockDescriptor size!");

		UnusedBlockHeap ret;
		foreach (i; 0 .. Count) {
			/**
			 * We create the elements starting from the last so that
			 * they are inserted in the heap from worst to best.
			 * This ensures the heap is a de facto linked list.
			 * */
			auto slot = page.add((Count - 1 - i) * BlockDescriptorSize);
			auto block = cast(BlockDescriptor*) slot.address;

			*block = BlockDescriptor(null, 0, slot.generation);
			ret.insert(block);
		}

		return ret;
	}

	@property
	bool empty() const {
		return usedCount == 0;
	}

	@property
	bool full() const {
		return usedCount >= PagesInBlock;
	}

	uint reserve(uint pages) {
		// FIXME: in contract
		assert(pages > 0 && pages <= longestFreeRange,
		       "Invalid number of pages!");

		uint bestIndex = uint.max;
		uint bestLength = uint.max;
		uint longestLength = 0;
		uint secondLongestLength = 0;

		uint current, index, length;
		while (current < PagesInBlock
			       && allocatedPages.nextFreeRange(current, index, length)) {
			assert(length <= longestFreeRange);

			// Keep track of the best length.
			if (length > longestLength) {
				secondLongestLength = longestLength;
				longestLength = length;
			} else if (length > secondLongestLength) {
				secondLongestLength = length;
			}

			if (length >= pages && length < bestLength) {
				bestIndex = index;
				bestLength = length;
			}

			current = index + length;
		}

		registerAllocation(bestIndex, pages);

		// If we allocated from the longest range,
		// compute the new longest free range.
		if (bestLength == longestLength) {
			longestLength = max(longestLength - pages, secondLongestLength);
		}

		longestFreeRange = longestLength;
		return bestIndex;
	}

	bool reserveAt(uint index, uint pages) {
		assert(index < PagesInBlock, "Invalid index!");
		assert(pages > 0 && index + pages <= PagesInBlock,
		       "Invalid number of pages!");

		auto freeLength = allocatedPages.findSet(index) - index;
		if (freeLength < pages) {
			return false;
		}

		registerAllocation(index, pages);

		// If not allocated from the longest free range, we're done:
		if (freeLength != longestFreeRange) {
			return true;
		}

		// TODO: We could stop at PagesInBlock - longestLength, but will require test.
		uint longestLength = 0;
		uint current = 0;
		uint length;
		while (current < PagesInBlock
			       && allocatedPages.nextFreeRange(current, current, length)) {
			if (length > longestLength) {
				longestLength = length;
			}

			current += length;
		}

		longestFreeRange = longestLength;
		return true;
	}

	void registerAllocation(uint index, uint pages) {
		assert(index < PagesInBlock, "Invalid index!");
		assert(pages > 0 && index + pages <= PagesInBlock,
		       "Invalid number of pages!");

		// Mark the pages as allocated.
		usedCount += pages;
		allocatedPages.setRange(index, pages);

		// Mark the pages as dirty.
		dirtyCount -= dirtyPages.countBits(index, pages);
		dirtyCount += pages;
		dirtyPages.setRange(index, pages);
	}

	void release(uint index, uint pages) {
		// FIXME: in contract.
		assert(pages > 0 && pages <= PagesInBlock, "Invalid number of pages!");
		assert(index <= PagesInBlock - pages, "Invalid index!");
		assert(allocatedPages.findClear(index) >= index + pages);

		allocatedPages.clearRange(index, pages);
		auto start = allocatedPages.findSetBackward(index) + 1;
		auto stop = allocatedPages.findSet(index + pages - 1);

		usedCount -= pages;
		longestFreeRange = max(longestFreeRange, stop - start);
	}
}

alias EpochBlockHeap = Heap!(BlockDescriptor, epochBlockCmp);

ptrdiff_t epochBlockCmp(BlockDescriptor* lhs, BlockDescriptor* rhs) {
	auto lg = lhs.epoch;
	auto rg = rhs.epoch;

	return (lg > rg) - (lg < rg);
}

alias UnusedBlockHeap = Heap!(BlockDescriptor, unusedBlockDescriptorCmp);

ptrdiff_t unusedBlockDescriptorCmp(BlockDescriptor* lhs, BlockDescriptor* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}

unittest blockDescriptor {
	BlockDescriptor block;

	void checkRangeState(uint nused, uint lfr) {
		assert(block.usedCount == nused);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	checkRangeState(0, PagesInBlock);

	// First allocation.
	assert(block.reserve(5) == 0);
	checkRangeState(5, PagesInBlock - 5);

	// Second allocation.
	assert(block.reserve(5) == 5);
	checkRangeState(10, PagesInBlock - 10);

	// Check that freeing the first allocation works as expected.
	block.release(0, 5);
	checkRangeState(5, PagesInBlock - 10);

	// A new allocation that doesn't fit in the space left
	// by the first one is done in the trailign space.
	assert(block.reserve(7) == 10);
	checkRangeState(12, PagesInBlock - 17);

	// A new allocation that fits is allocated in there.
	assert(block.reserve(5) == 0);
	checkRangeState(17, PagesInBlock - 17);

	// Make sure we keep track of the longest free range
	// when releasing pages.
	block.release(10, 7);
	checkRangeState(10, PagesInBlock - 10);

	block.release(0, 5);
	checkRangeState(5, PagesInBlock - 10);

	block.release(5, 5);
	checkRangeState(0, PagesInBlock);

	// Allocate the whole block.
	foreach (i; 0 .. PagesInBlock / 4) {
		assert(block.reserve(4) == 4 * i);
	}

	checkRangeState(PagesInBlock, 0);

	// Release in the middle.
	block.release(100, 4);
	checkRangeState(PagesInBlock - 4, 4);

	// Release just before and after.
	block.release(104, 4);
	checkRangeState(PagesInBlock - 8, 8);

	block.release(96, 4);
	checkRangeState(PagesInBlock - 12, 12);

	// Release futher along and then bridge.
	block.release(112, 4);
	checkRangeState(PagesInBlock - 16, 12);

	block.release(108, 4);
	checkRangeState(PagesInBlock - 20, 20);

	// Release first and last.
	block.release(0, 4);
	checkRangeState(PagesInBlock - 24, 20);

	block.release(PagesInBlock - 4, 4);
	checkRangeState(PagesInBlock - 28, 20);
}

unittest blockDescriptorClear {
	BlockDescriptor block;

	void checkRangeState(uint nused, uint lfr) {
		assert(block.usedCount == nused);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	// First allocation.
	assert(block.reserve(200) == 0);
	checkRangeState(200, PagesInBlock - 200);

	// Second allocation:
	assert(block.reserve(100) == 200);
	checkRangeState(300, PagesInBlock - 300);

	// Third allocation, and we're full:
	assert(block.reserve(212) == 300);
	checkRangeState(512, 0);

	// Shrink the first allocation, make lfr of 100:
	block.release(100, 100);
	checkRangeState(412, PagesInBlock - 412);

	// Shrink the second allocation, lfr is still 100:
	block.release(299, 1);
	checkRangeState(411, PagesInBlock - 412);

	// Shrink the third allocation, lfr is still 100:
	block.release(500, 12);
	checkRangeState(399, PagesInBlock - 412);

	// Release the third allocation:
	block.release(300, 200);
	checkRangeState(199, 213);

	// Release the second allocation:
	block.release(200, 99);
	checkRangeState(100, PagesInBlock - 100);

	// Release the first allocation:
	block.release(0, 100);
	checkRangeState(0, PagesInBlock);
}

unittest blockDescriptorGrowAllocations {
	BlockDescriptor block;

	void checkRangeState(uint nused, uint lfr) {
		assert(block.usedCount == nused);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	checkRangeState(0, PagesInBlock);

	// First allocation:
	assert(block.reserve(64) == 0);
	checkRangeState(64, PagesInBlock - 64);

	// Grow it by 32 pages:
	assert(block.reserveAt(64, 32));
	checkRangeState(96, PagesInBlock - 96);

	// Grow it by another 32 pages:
	assert(block.reserveAt(96, 32));
	checkRangeState(128, PagesInBlock - 128);

	// Second allocation:
	assert(block.reserve(256) == 128);
	checkRangeState(384, PagesInBlock - 384);

	// Try to grow the first allocation, but cannot, there is no space:
	assert(!block.reserveAt(128, 1));

	// Third allocation:
	assert(block.reserve(128) == 384);
	checkRangeState(512, 0);

	// Try to grow the second allocation, but cannot, there is no space:
	assert(!block.reserveAt(384, 1));

	// Release first allocation:
	block.release(0, 128);
	checkRangeState(384, PagesInBlock - 384);

	// Release third allocation:
	block.release(384, 128);
	checkRangeState(256, 128);

	// There are now two equally 'longest length' free ranges.
	// Grow the second allocation to see that lfr is recomputed properly:
	assert(block.reserveAt(384, 1));
	checkRangeState(257, 128);

	// Make an allocation in the lfr, new lfr is after the second alloc:
	assert(block.reserve(128) == 0);
	checkRangeState(385, 127);

	// Free the above allocation, lfr is 128 again:
	block.release(0, 128);
	checkRangeState(257, 128);

	// Free the second allocation:
	block.release(128, 257);
	checkRangeState(0, PagesInBlock);

	// Test with a full block:

	// Make an allocation:
	assert(block.reserve(256) == 0);
	checkRangeState(256, PagesInBlock - 256);

	// Make another allocation, filling block:
	assert(block.reserve(256) == 256);
	checkRangeState(512, 0);

	// Try expanding the first one, but there is no space:
	assert(!block.reserveAt(256, 1));

	// Release the first allocation:
	block.release(0, 256);
	checkRangeState(256, PagesInBlock - 256);

	// Replace it with a shorter one:
	assert(block.reserve(250) == 0);
	checkRangeState(506, PagesInBlock - 506);

	// Try to grow the above by 7, but cannot, this is one page too many:
	assert(!block.reserveAt(250, 7));

	// Grow by 6 works, and fills block:
	assert(block.reserveAt(250, 6));
	checkRangeState(512, 0);
}
