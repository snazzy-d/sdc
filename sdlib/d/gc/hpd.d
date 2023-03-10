module d.gc.hpd;

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
	ulong generation;

	uint allocCount;
	uint usedCount;
	uint longestFreeRange = PageCount;

	import d.gc.heap;
	Node!HugePageDescriptor phnode;

	enum PageCount = HugePageSize / PageSize;

	import d.gc.bitmap;
	Bitmap!PageCount allocatedPages;

public:
	this(void* address, ulong generation) {
		this.address = address;
		this.generation = generation;
	}

	uint reserve(uint pages) {
		// FIXME: in contract
		assert(pages <= longestFreeRange);

		uint bestIndex = uint.max;
		uint bestLength = uint.max;
		uint longestLength = 0;
		uint secondLongestLength = 0;

		uint current, index, length;
		while (current < PageCount
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

		assert(bestIndex < PageCount);
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

	void release(uint index, uint pages) {
		// FIXME: in contract.
		assert(allocatedPages.findClear(index) >= index + pages);

		allocatedPages.clearRange(index, pages);
		auto start = allocatedPages.findSetBackward(index) + 1;
		auto stop = allocatedPages.findSet(index + pages);

		allocCount--;
		usedCount -= pages;
		longestFreeRange = max(longestFreeRange, stop - start);
	}
}

unittest hugePageDescriptor {
	enum PageCount = HugePageDescriptor.PageCount;
	HugePageDescriptor hpd;

	void checkRangeState(uint nalloc, uint nused, uint lfr) {
		assert(hpd.allocCount == nalloc);
		assert(hpd.usedCount == nused);
		assert(hpd.longestFreeRange == lfr);
		assert(hpd.allocatedPages.countBits(0, PageCount) == nused);
	}

	checkRangeState(0, 0, PageCount);

	// First allocation.
	assert(hpd.reserve(5) == 0);
	checkRangeState(1, 5, PageCount - 5);

	// Second allocation.
	assert(hpd.reserve(5) == 5);
	checkRangeState(2, 10, PageCount - 10);

	// Check that freeing the first allocation works as expected.
	hpd.release(0, 5);
	checkRangeState(1, 5, PageCount - 10);

	// A new allocation that doesn't fit in the space left
	// by the first one is done in the trailign space.
	assert(hpd.reserve(7) == 10);
	checkRangeState(2, 12, PageCount - 17);

	// A new allocation that fits is allocated in there.
	assert(hpd.reserve(5) == 0);
	checkRangeState(3, 17, PageCount - 17);

	// Make sure we keep track of the longest free range
	// when releasing pages.
	hpd.release(10, 7);
	checkRangeState(2, 10, PageCount - 10);

	hpd.release(0, 5);
	checkRangeState(1, 5, PageCount - 10);

	hpd.release(5, 5);
	checkRangeState(0, 0, PageCount);

	// Allocate the whole block.
	foreach (i; 0 .. PageCount / 4) {
		assert(hpd.reserve(4) == 4 * i);
	}

	checkRangeState(PageCount / 4, PageCount, 0);

	// Release int he middle.
	hpd.release(100, 4);
	checkRangeState(PageCount / 4 - 1, PageCount - 4, 4);

	// Release just before and after.
	hpd.release(104, 4);
	checkRangeState(PageCount / 4 - 2, PageCount - 8, 8);

	hpd.release(96, 4);
	checkRangeState(PageCount / 4 - 3, PageCount - 12, 12);

	// Release futher along and then bridge.
	hpd.release(112, 4);
	checkRangeState(PageCount / 4 - 4, PageCount - 16, 12);

	hpd.release(108, 4);
	checkRangeState(PageCount / 4 - 5, PageCount - 20, 20);
}
