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

	import d.gc.heap;
	Node!BlockDescriptor phnode;

	uint longestFreeRange = PagesInBlock;
	uint allocScore = PagesInBlock;

	uint usedCount;
	uint dirtyCount;
	ubyte generation;

	import d.gc.bitmap;
	Bitmap!PagesInBlock allocatedPages;
	Bitmap!PagesInBlock dirtyPages;

	this(void* address, ubyte generation = 0) {
		this.address = address;
		this.generation = generation;
	}

public:
	BlockDescriptor* at(void* ptr) {
		this = BlockDescriptor(ptr, generation);
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

			*block = BlockDescriptor(null, slot.generation);
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

	@property
	uint allocCount() const {
		return PagesInBlock - allocScore;
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

		allocScore--;
		registerAllocation(bestIndex, pages);

		// If we allocated from the longest range,
		// compute the new longest free range.
		if (bestLength == longestLength) {
			longestLength = max(longestLength - pages, secondLongestLength);
		}

		longestFreeRange = longestLength;
		return bestIndex;
	}

	bool growAt(uint index, uint pages) {
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
			longestLength = max(longestLength, length);
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

	void clear(uint index, uint pages) {
		// FIXME: in contract.
		assert(pages > 0 && pages <= PagesInBlock, "Invalid number of pages!");
		assert(index <= PagesInBlock - pages, "Invalid index!");
		assert(allocatedPages.countBits(index, pages) == pages,
		       "Clearing unallocated pages!");

		allocatedPages.clearRange(index, pages);
		auto start = allocatedPages.findSetBackward(index) + 1;
		auto stop = allocatedPages.findSet(index + pages - 1);

		usedCount -= pages;
		longestFreeRange = max(longestFreeRange, stop - start);
	}

	void release(uint index, uint pages) {
		clear(index, pages);
		allocScore++;
	}
}

alias PriorityBlockHeap = Heap!(BlockDescriptor, priorityBlockCmp);

ptrdiff_t priorityBlockCmp(BlockDescriptor* lhs, BlockDescriptor* rhs) {
	/**
	 * Our first priority is to reduce fragmentation.
	 * We therefore try to select the block with the shortest
	 * free range possible, so we avoid unecesserly breaking
	 * large free ranges.
	 */
	auto l = ulong(lhs.longestFreeRange) << 48;
	auto r = ulong(rhs.longestFreeRange) << 48;

	/**
	 * Our second priority is the number of allocation in the block.
	 * We do so in order to maximize our chances to be able to free blocks.
	 * 
	 * This tends to work better in practice than counting the number
	 * of allocated pages or other metrics. For details, please see the
	 * Temeraire paper: https://research.google/pubs/pub50370/
	 * 
	 * The intuition is that the more allocation live on a block,
	 * the more likely one of them is goign to be long lived.
	 */
	l |= ulong(lhs.allocScore) << 32;
	r |= ulong(rhs.allocScore) << 32;

	// We must shift the address itself so it doesn't collide.
	// Block alignement is > 16 bits so it's all zeros.
	static assert(LgBlockSize > 16, "Blocks too small!");
	l |= (cast(size_t) lhs) >> 16;
	r |= (cast(size_t) rhs) >> 16;

	return (l > r) - (l < r);
}

unittest priority {
	static makeBlock(uint lfr, uint nalloc) {
		BlockDescriptor block;
		block.longestFreeRange = lfr;
		block.allocScore = PagesInBlock - nalloc;

		assert(block.allocCount == nalloc);
		return block;
	}

	PriorityBlockHeap heap;
	assert(heap.top is null);

	// Lowest priority block possible.
	auto block0 = makeBlock(PagesInBlock, 0);
	heap.insert(&block0);
	assert(heap.top is &block0);

	// More allocation is better.
	auto block1 = makeBlock(PagesInBlock, 1);
	heap.insert(&block1);
	assert(heap.top is &block1);

	// But shorter lfr is even better!
	auto block2 = makeBlock(0, 0);
	heap.insert(&block2);
	assert(heap.top is &block2);

	// More allocation remains a tie breaker.
	auto block3 = makeBlock(0, 500);
	heap.insert(&block3);
	assert(heap.top is &block3);

	// Try inserting a few blocks out of order.
	auto block4 = makeBlock(0, 100);
	auto block5 = makeBlock(250, 1);
	auto block6 = makeBlock(250, 300);
	auto block7 = makeBlock(100, 300);
	heap.insert(&block4);
	heap.insert(&block5);
	heap.insert(&block6);
	heap.insert(&block7);

	// Pop all the blocks and check they come out in
	// the expected order.
	assert(heap.pop() is &block3);
	assert(heap.pop() is &block4);
	assert(heap.pop() is &block2);
	assert(heap.pop() is &block7);
	assert(heap.pop() is &block6);
	assert(heap.pop() is &block5);
	assert(heap.pop() is &block1);
	assert(heap.pop() is &block0);
	assert(heap.pop() is null);
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

unittest reserve_release {
	BlockDescriptor block;

	void checkRangeState(uint nalloc, uint nused, uint ndirty, uint lfr) {
		assert(block.allocCount == nalloc);
		assert(block.usedCount == nused);
		assert(block.dirtyCount == ndirty);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	checkRangeState(0, 0, 0, PagesInBlock);

	// First allocation.
	assert(block.reserve(5) == 0);
	checkRangeState(1, 5, 5, PagesInBlock - 5);

	// Second allocation.
	assert(block.reserve(5) == 5);
	checkRangeState(2, 10, 10, PagesInBlock - 10);

	// Check that freeing the first allocation works as expected.
	block.release(0, 5);
	checkRangeState(1, 5, 10, PagesInBlock - 10);

	// A new allocation that doesn't fit in the space left
	// by the first one is done in the trailign space.
	assert(block.reserve(7) == 10);
	checkRangeState(2, 12, 17, PagesInBlock - 17);

	// A new allocation that fits is allocated in there.
	assert(block.reserve(5) == 0);
	checkRangeState(3, 17, 17, PagesInBlock - 17);

	// Make sure we keep track of the longest free range
	// when releasing pages.
	block.release(10, 7);
	checkRangeState(2, 10, 17, PagesInBlock - 10);

	block.release(0, 5);
	checkRangeState(1, 5, 17, PagesInBlock - 10);

	block.release(5, 5);
	checkRangeState(0, 0, 17, PagesInBlock);

	// Allocate the whole block.
	foreach (i; 0 .. PagesInBlock / 4) {
		assert(block.reserve(4) == 4 * i);
	}

	checkRangeState(PagesInBlock / 4, PagesInBlock, 512, 0);

	// Release in the middle.
	block.release(100, 4);
	checkRangeState(PagesInBlock / 4 - 1, PagesInBlock - 4, 512, 4);

	// Release just before and after.
	block.release(104, 4);
	checkRangeState(PagesInBlock / 4 - 2, PagesInBlock - 8, 512, 8);

	block.release(96, 4);
	checkRangeState(PagesInBlock / 4 - 3, PagesInBlock - 12, 512, 12);

	// Release futher along and then bridge.
	block.release(112, 4);
	checkRangeState(PagesInBlock / 4 - 4, PagesInBlock - 16, 512, 12);

	block.release(108, 4);
	checkRangeState(PagesInBlock / 4 - 5, PagesInBlock - 20, 512, 20);

	// Release first and last.
	block.release(0, 4);
	checkRangeState(PagesInBlock / 4 - 6, PagesInBlock - 24, 512, 20);

	block.release(PagesInBlock - 4, 4);
	checkRangeState(PagesInBlock / 4 - 7, PagesInBlock - 28, 512, 20);
}

unittest clear {
	BlockDescriptor block;

	void checkRangeState(uint nalloc, uint nused, uint ndirty, uint lfr) {
		assert(block.allocCount == nalloc);
		assert(block.usedCount == nused);
		assert(block.dirtyCount == ndirty);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	// First allocation.
	assert(block.reserve(200) == 0);
	checkRangeState(1, 200, 200, PagesInBlock - 200);

	// Second allocation:
	assert(block.reserve(100) == 200);
	checkRangeState(2, 300, 300, PagesInBlock - 300);

	// Third allocation, and we're full:
	assert(block.reserve(212) == 300);
	checkRangeState(3, 512, 512, 0);

	// Shrink the first allocation, make lfr of 100.
	block.clear(100, 100);
	checkRangeState(3, 412, 512, PagesInBlock - 412);

	// Shrink the second allocation, lfr is still 100.
	block.clear(299, 1);
	checkRangeState(3, 411, 512, PagesInBlock - 412);

	// Shrink the third allocation, lfr is still 100.
	block.clear(500, 12);
	checkRangeState(3, 399, 512, PagesInBlock - 412);

	// Release the third allocation.
	block.release(300, 200);
	checkRangeState(2, 199, 512, 213);

	// Release the second allocation.
	block.release(200, 99);
	checkRangeState(1, 100, 512, PagesInBlock - 100);

	// Release the first allocation.
	block.release(0, 100);
	checkRangeState(0, 0, 512, PagesInBlock);
}

unittest growAt {
	BlockDescriptor block;

	void checkRangeState(uint nalloc, uint nused, uint ndirty, uint lfr) {
		assert(block.allocCount == nalloc);
		assert(block.usedCount == nused);
		assert(block.dirtyCount == ndirty);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	checkRangeState(0, 0, 0, PagesInBlock);

	// First allocation.
	assert(block.reserve(64) == 0);
	checkRangeState(1, 64, 64, PagesInBlock - 64);

	// Grow it by 32 pages.
	assert(block.growAt(64, 32));
	checkRangeState(1, 96, 96, PagesInBlock - 96);

	// Grow it by another 32 pages.
	assert(block.growAt(96, 32));
	checkRangeState(1, 128, 128, PagesInBlock - 128);

	// Second allocation.
	assert(block.reserve(256) == 128);
	checkRangeState(2, 384, 384, PagesInBlock - 384);

	// Try to grow the first allocation, but cannot, there is no space.
	assert(!block.growAt(128, 1));
	checkRangeState(2, 384, 384, PagesInBlock - 384);

	// Third allocation.
	assert(block.reserve(128) == 384);
	checkRangeState(3, 512, 512, 0);

	// Try to grow the second allocation, but cannot, there is no space.
	assert(!block.growAt(384, 1));
	checkRangeState(3, 512, 512, 0);

	// Release first allocation.
	block.release(0, 128);
	checkRangeState(2, 384, 512, PagesInBlock - 384);

	// Release third allocation.
	block.release(384, 128);
	checkRangeState(1, 256, 512, 128);

	// There are now two equally 'longest length' free ranges.
	// Grow the second allocation to see that lfr is recomputed properly.
	assert(block.growAt(384, 1));
	checkRangeState(1, 257, 512, 128);

	// Make an allocation in the lfr, new lfr is after the second alloc.
	assert(block.reserve(128) == 0);
	checkRangeState(2, 385, 512, 127);

	// Free the above allocation, lfr is 128 again.
	block.release(0, 128);
	checkRangeState(1, 257, 512, 128);

	// Free the second allocation.
	block.release(128, 257);
	checkRangeState(0, 0, 512, PagesInBlock);

	// Test with a full block:

	// Make an allocation:
	assert(block.reserve(256) == 0);
	checkRangeState(1, 256, 512, PagesInBlock - 256);

	// Make another allocation, filling block.
	assert(block.reserve(256) == 256);
	checkRangeState(2, 512, 512, 0);

	// Try expanding the first one, but there is no space.
	assert(!block.growAt(256, 1));
	checkRangeState(2, 512, 512, 0);

	// Release the first allocation.
	block.release(0, 256);
	checkRangeState(1, 256, 512, PagesInBlock - 256);

	// Replace it with a shorter one.
	assert(block.reserve(250) == 0);
	checkRangeState(2, 506, 512, PagesInBlock - 506);

	// Try to grow the above by 7, but cannot, this is one page too many.
	assert(!block.growAt(250, 7));
	checkRangeState(2, 506, 512, PagesInBlock - 506);

	// Grow by 6 works, and fills block.
	assert(block.growAt(250, 6));
	checkRangeState(2, 512, 512, 0);
}

unittest track_dirty {
	BlockDescriptor block;

	void checkRangeState(uint nalloc, uint nused, uint ndirty, uint lfr) {
		assert(block.allocCount == nalloc);
		assert(block.usedCount == nused);
		assert(block.dirtyCount == ndirty);
		assert(block.longestFreeRange == lfr);
		assert(block.allocatedPages.countBits(0, PagesInBlock) == nused);
	}

	checkRangeState(0, 0, 0, PagesInBlock);

	// First allocation.
	assert(block.reserve(5) == 0);
	checkRangeState(1, 5, 5, PagesInBlock - 5);

	// Second allocation.
	assert(block.reserve(5) == 5);
	checkRangeState(2, 10, 10, PagesInBlock - 10);

	// Check that freeing the first allocation works as expected.
	block.release(0, 5);
	checkRangeState(1, 5, 10, PagesInBlock - 10);

	// A new allocation that doesn't fit in the space left
	// by the first one is done in the trailign space.
	assert(block.reserve(7) == 10);
	checkRangeState(2, 12, 17, PagesInBlock - 17);

	// A new allocation that fits is allocated in there.
	assert(block.reserve(5) == 0);
	checkRangeState(3, 17, 17, PagesInBlock - 17);

	// Make sure we keep track of the longest free range
	// when releasing pages.
	block.release(10, 7);
	checkRangeState(2, 10, 17, PagesInBlock - 10);

	block.release(0, 5);
	checkRangeState(1, 5, 17, PagesInBlock - 10);

	// Check that allocating something that do not fit in
	// the first slot allocates in the apropriate free range.
	assert(block.reserve(10) == 10);
	checkRangeState(2, 15, 20, PagesInBlock - 20);
}
