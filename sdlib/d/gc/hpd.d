module d.gc.hpd;

import d.gc.base;
import d.gc.spec;
import d.gc.util;

/**
 * Each HugePageDescriptor manages a system's huge page.
 *
 * In order to reduce TLB pressure, we try to layout the momery in
 * such a way that the OS can back it with huge pages. We organise
 * the memory in block that correspond to a huge page, and allocate
 * in block that are unlikely to empty themselves any time soon.
 */
struct HugePageDescriptor {
private:
	void* address;
	ulong epoch;

	uint allocCount;
	uint usedCount;
	uint longestFreeRange = PagesInHugePage;
	ubyte generation;

	import d.gc.heap;
	Node!HugePageDescriptor phnode;

	import d.gc.bitmap;
	Bitmap!PagesInHugePage allocatedPages;

	this(void* address, ulong epoch, ubyte generation = 0) {
		this.address = address;
		this.epoch = epoch;
		this.generation = generation;
	}

public:
	HugePageDescriptor* at(void* ptr, ulong epoch) {
		this = HugePageDescriptor(ptr, epoch, generation);
		return &this;
	}

	static fromSlot(Base.Slot slot) {
		// FIXME: in contract
		assert(slot.address !is null, "Slot is empty!");

		static assert(HugePageDescriptor.sizeof <= ExtentSize,
		              "Unexpected HugePageDescriptor size!");

		auto hpd = cast(HugePageDescriptor*) slot.address;
		*hpd = HugePageDescriptor(null, 0, slot.generation);
		return hpd;
	}

	@property
	bool empty() const {
		return usedCount == 0;
	}

	@property
	bool full() const {
		return usedCount >= PagesInHugePage;
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
		while (current < PagesInHugePage
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

		assert(bestIndex < PagesInHugePage);
		allocatedPages.setRange(bestIndex, pages);

		// If we allocated from the longest range,
		// compute the new longest free range.
		if (bestLength == longestLength) {
			longestLength = max(longestLength - pages, secondLongestLength);
		}

		allocCount++;
		usedCount += pages;
		longestFreeRange = longestLength;

		return bestIndex;
	}

	bool set(uint index, uint pages) {
		assert(pages > 0 && pages <= PagesInHugePage,
		       "Invalid number of pages!");
		assert(index <= PagesInHugePage - pages, "Invalid index!");

		auto freeLength = allocatedPages.findSet(index) - index;
		if (freeLength < pages) {
			return false;
		}

		allocatedPages.setRange(index, pages);
		usedCount += pages;

		// If not allocated from the longest free range, we're done:
		if (freeLength != longestFreeRange) {
			return true;
		}

		// TODO: We could stop at PagesInHugePage - longestLength, but will require test.
		uint longestLength = 0;
		uint current = 0;
		uint length;
		while (current < PagesInHugePage
			       && allocatedPages.nextFreeRange(current, index, length)) {
			if (length > longestLength) {
				longestLength = length;
			}

			current = index + length;
		}

		longestFreeRange = longestLength;
		return true;
	}

	void clear(uint index, uint pages) {
		// FIXME: in contract.
		assert(pages > 0 && pages <= PagesInHugePage,
		       "Invalid number of pages!");
		assert(index <= PagesInHugePage - pages, "Invalid index!");
		assert(allocatedPages.findClear(index) >= index + pages);

		allocatedPages.clearRange(index, pages);
		auto start = allocatedPages.findSetBackward(index) + 1;
		auto stop = allocatedPages.findSet(index + pages - 1);

		usedCount -= pages;
		longestFreeRange = max(longestFreeRange, stop - start);
	}

	void release(uint index, uint pages) {
		clear(index, pages);
		allocCount--;
	}
}

ptrdiff_t epochHPDCmp(HugePageDescriptor* lhs, HugePageDescriptor* rhs) {
	auto lg = lhs.epoch;
	auto rg = rhs.epoch;

	return (lg > rg) - (lg < rg);
}

ptrdiff_t unusedHPDCmp(HugePageDescriptor* lhs, HugePageDescriptor* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}

unittest hugePageDescriptor {
	HugePageDescriptor hpd;

	void checkRangeState(uint nalloc, uint nused, uint lfr) {
		assert(hpd.allocCount == nalloc);
		assert(hpd.usedCount == nused);
		assert(hpd.longestFreeRange == lfr);
		assert(hpd.allocatedPages.countBits(0, PagesInHugePage) == nused);
	}

	checkRangeState(0, 0, PagesInHugePage);

	// First allocation.
	assert(hpd.reserve(5) == 0);
	checkRangeState(1, 5, PagesInHugePage - 5);

	// Second allocation.
	assert(hpd.reserve(5) == 5);
	checkRangeState(2, 10, PagesInHugePage - 10);

	// Check that freeing the first allocation works as expected.
	hpd.release(0, 5);
	checkRangeState(1, 5, PagesInHugePage - 10);

	// A new allocation that doesn't fit in the space left
	// by the first one is done in the trailign space.
	assert(hpd.reserve(7) == 10);
	checkRangeState(2, 12, PagesInHugePage - 17);

	// A new allocation that fits is allocated in there.
	assert(hpd.reserve(5) == 0);
	checkRangeState(3, 17, PagesInHugePage - 17);

	// Make sure we keep track of the longest free range
	// when releasing pages.
	hpd.release(10, 7);
	checkRangeState(2, 10, PagesInHugePage - 10);

	hpd.release(0, 5);
	checkRangeState(1, 5, PagesInHugePage - 10);

	hpd.release(5, 5);
	checkRangeState(0, 0, PagesInHugePage);

	// Allocate the whole block.
	foreach (i; 0 .. PagesInHugePage / 4) {
		assert(hpd.reserve(4) == 4 * i);
	}

	checkRangeState(PagesInHugePage / 4, PagesInHugePage, 0);

	// Release in the middle.
	hpd.release(100, 4);
	checkRangeState(PagesInHugePage / 4 - 1, PagesInHugePage - 4, 4);

	// Release just before and after.
	hpd.release(104, 4);
	checkRangeState(PagesInHugePage / 4 - 2, PagesInHugePage - 8, 8);

	hpd.release(96, 4);
	checkRangeState(PagesInHugePage / 4 - 3, PagesInHugePage - 12, 12);

	// Release futher along and then bridge.
	hpd.release(112, 4);
	checkRangeState(PagesInHugePage / 4 - 4, PagesInHugePage - 16, 12);

	hpd.release(108, 4);
	checkRangeState(PagesInHugePage / 4 - 5, PagesInHugePage - 20, 20);

	// Release first and last.
	hpd.release(0, 4);
	checkRangeState(PagesInHugePage / 4 - 6, PagesInHugePage - 24, 20);

	hpd.release(PagesInHugePage - 4, 4);
	checkRangeState(PagesInHugePage / 4 - 7, PagesInHugePage - 28, 20);
}

unittest hugePageDescriptorClear {
	HugePageDescriptor hpd;

	void checkRangeState(uint nalloc, uint nused, uint lfr) {
		assert(hpd.allocCount == nalloc);
		assert(hpd.usedCount == nused);
		assert(hpd.longestFreeRange == lfr);
		assert(hpd.allocatedPages.countBits(0, PagesInHugePage) == nused);
	}

	// First allocation.
	assert(hpd.reserve(200) == 0);
	checkRangeState(1, 200, PagesInHugePage - 200);

	// Second allocation:
	assert(hpd.reserve(100) == 200);
	checkRangeState(2, 300, PagesInHugePage - 300);

	// Third allocation, and we're full:
	assert(hpd.reserve(212) == 300);
	checkRangeState(3, 512, 0);

	// Shrink the first allocation, make lfr of 100:
	hpd.clear(100, 100);
	checkRangeState(3, 412, PagesInHugePage - 412);

	// Shrink the second allocation, lfr is still 100:
	hpd.clear(299, 1);
	checkRangeState(3, 411, PagesInHugePage - 412);

	// Shrink the third allocation, lfr is still 100:
	hpd.clear(500, 12);
	checkRangeState(3, 399, PagesInHugePage - 412);

	// Release the third allocation:
	hpd.release(300, 200);
	checkRangeState(2, 199, 213);

	// Release the second allocation:
	hpd.release(200, 99);
	checkRangeState(1, 100, PagesInHugePage - 100);

	// Release the first allocation:
	hpd.release(0, 100);
	checkRangeState(0, 0, PagesInHugePage);
}

unittest hugePageDescriptorGrowAllocations {
	HugePageDescriptor hpd;

	void checkRangeState(uint nalloc, uint nused, uint lfr) {
		assert(hpd.allocCount == nalloc);
		assert(hpd.usedCount == nused);
		assert(hpd.longestFreeRange == lfr);
		assert(hpd.allocatedPages.countBits(0, PagesInHugePage) == nused);
	}

	checkRangeState(0, 0, PagesInHugePage);

	// First allocation:
	assert(hpd.reserve(64) == 0);
	checkRangeState(1, 64, PagesInHugePage - 64);

	// Grow it by 32 pages:
	assert(hpd.set(64, 32));
	checkRangeState(1, 96, PagesInHugePage - 96);

	// Grow it by another 32 pages:
	assert(hpd.set(96, 32));
	checkRangeState(1, 128, PagesInHugePage - 128);

	// Second allocation:
	assert(hpd.reserve(256) == 128);
	checkRangeState(2, 384, PagesInHugePage - 384);

	// Try to grow the first allocation, but cannot, there is no space:
	assert(!hpd.set(128, 1));

	// Third allocation:
	assert(hpd.reserve(128) == 384);
	checkRangeState(3, 512, 0);

	// Try to grow the second allocation, but cannot, there is no space:
	assert(!hpd.set(384, 1));

	// Release first allocation:
	hpd.release(0, 128);
	checkRangeState(2, 384, PagesInHugePage - 384);

	// Release third allocation:
	hpd.release(384, 128);
	checkRangeState(1, 256, 128);

	// There are now two equally 'longest length' free ranges.
	// Grow the second allocation to see that lfr is recomputed properly:
	assert(hpd.set(384, 1));
	checkRangeState(1, 257, 128);

	// Make an allocation in the lfr, new lfr is after the second alloc:
	assert(hpd.reserve(128) == 0);
	checkRangeState(2, 385, 127);

	// Free the above allocation, lfr is 128 again:
	hpd.release(0, 128);
	checkRangeState(1, 257, 128);

	// Free the second allocation:
	hpd.release(128, 257);
	checkRangeState(0, 0, PagesInHugePage);

	// Test with a full HPD:

	// Make an allocation:
	assert(hpd.reserve(256) == 0);
	checkRangeState(1, 256, PagesInHugePage - 256);

	// Make another allocation, filling hpd:
	assert(hpd.reserve(256) == 256);
	checkRangeState(2, 512, 0);

	// Try expanding the first one, but there is no space :
	assert(!hpd.set(256, 1));

	// Release the first allocation:
	hpd.release(0, 256);
	checkRangeState(1, 256, PagesInHugePage - 256);

	// Replace it with a shorter one:
	assert(hpd.reserve(250) == 0);
	checkRangeState(2, 506, PagesInHugePage - 506);

	// Try to grow the above by 7, but cannot, this is one page too many:
	assert(!hpd.set(250, 7));

	// Grow by 6 works, and fills hpd:
	assert(hpd.set(250, 6));
	checkRangeState(2, 512, 0);
}
