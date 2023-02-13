module d.gc.base;

import d.gc.extent;
import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

struct Block {
	size_t size;
	Block* next;

	Extent extent;
}

/**
 * Bump the pointer style allocator.
 *
 * It never deallocates, except on destruction.
 * It serves as a base allocator for address space.
 *
 * Note: We waste a fair amount of address space when
 * allocating with large alignment constraints. This is
 * not a huge deal per se because there is no memory
 * actually backing this address space, but this might
 * lead to various ineffisciencies.
 */
struct Base {
private:
	import d.sync.mutex;
	Mutex mutex;

	import d.gc.arena;
	Arena* arena;

	/**
	 * In order to avoid address space fragmentation,
	 * we allocate larger and larger blocks of addresses.
	 *
	 * We do so by remembering the size class we used and
	 * bump by 1. This ensure the block size we allocate
	 * grows exponentially.
	 */
	ubyte lastSizeClass;

	// Serial number generation?
	size_t nextSerialNumber;

	// Linked list of all the blocks.
	Block* head;

	// Free extents we can allocate to arenas.
	import d.gc.rbtree, d.gc.extent;
	RBTree!(Extent, sizeAddrExtentCmp) availableExtents;

	// TODO: Keep track of stats.
	// TODO: Support transparent huge pages?

public:
	void clear() shared {
		(cast(Base*) &this).clearImpl();
	}

	void* alloc(size_t size, size_t alignment) shared {
		return (cast(Base*) &this).allocImpl(size, alignment);
	}

private:
	void clearImpl() {
		mutex.lock();
		scope(exit) mutex.unlock();

		auto next = head;
		while (next !is null) {
			auto block = next;
			next = block.next;

			import d.gc.pages;
			pages_unmap(block, block.size);
		}
	}

	void* allocImpl(size_t size, size_t alignment) {
		alignment = alignUp(alignment, Quantum);
		size = alignUp(size, alignment);
		auto sc = getSizeClass(size + alignment - Quantum);

		mutex.lock();
		scope(exit) mutex.unlock();

		auto extent = availableExtents.extractBestFit(cast(Extent*) sc);
		if (extent is null) {
			extent = extentAlloc(size, alignment);
		}

		if (extent is null) {
			return null;
		}

		return extentBumpAlloc(extent, size, alignment);
	}

	Extent* extentAlloc(size_t size, size_t alignment) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(isAligned(alignment, Quantum), "Invalid alignement!");
		assert(isAligned(size, alignment), "Invalid size!");

		auto block = blockAlloc(size, alignment, lastSizeClass);
		if (block is null) {
			return null;
		}

		// Keep track of the last block size.
		lastSizeClass = getSizeClass(block.size);

		// Serial number.
		block.extent.serialNumber = nextSerialNumber++;

		// Add the newly allocated block to the list of blocks.
		block.next = head;
		head = block;

		return &block.extent;
	}

	void* extentBumpAlloc(Extent* extent, size_t size, size_t alignment) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(isAligned(alignment, Quantum), "Invalid alignement!");
		assert(isAligned(size, alignment), "Invalid size!");

		auto p = cast(size_t) extent.addr;
		auto gap = alignUp(p, alignment) - p;
		auto ret = extent.addr + gap;

		assert(extent.size >= size + gap, "Insufiscient space in the Extent!");
		extent.addr = ret + size;
		extent.size -= gap + size;

		availableExtents.insert(extent);
		return ret;
	}

	Block* blockAlloc(size_t size, size_t alignment, ubyte lastSizeClass) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(isAligned(alignment, Quantum), "Invalid alignement!");
		assert(isAligned(size, alignment), "Invalid size!");

		mutex.unlock();
		scope(exit) mutex.lock();

		auto headerSize = alignUp(Block.sizeof, alignment);

		/**
		 * We make sure we allocate at least a huge page, to leave the
		 * kernel the opportunity to use huge pages.
		 *
		 * We also increase the size of the block exponentially by bumping
		 * to the next size class if apropriate. This ensures we do not
		 * fragment the address space more than necessary and limit degenerate
		 * cases where we call into the base allocator again and again.
		 */
		auto minBlockSize = getAllocSize(headerSize + size);
		auto nextSizeClass =
			lastSizeClass + (lastSizeClass < ClassCount.Total - 1);
		auto nextBlockSize = getSizeFromBinID(nextSizeClass);
		auto baseBlockSize =
			(nextBlockSize < minBlockSize) ? minBlockSize : nextBlockSize;
		auto blockSize = alignUp(baseBlockSize, HugePageSize);

		import d.gc.pages;
		auto block = cast(Block*) pages_map(null, blockSize, HugePageSize);
		if (block is null) {
			return null;
		}

		block.size = blockSize;
		block.extent.addr = (cast(void*) block) + headerSize;
		block.extent.size = blockSize - headerSize;

		return block;
	}
}

unittest base_alloc {
	shared Base base;
	scope(exit) base.clear();

	auto getBlockCount(shared ref Base base) {
		size_t count = 0;

		auto next = base.head;
		while (next !is null) {
			count++;
			next = next.next;
		}

		return count;
	}

	assert(getBlockCount(base) == 0);

	auto ptr0 = base.alloc(5, 1);
	assert(getBlockCount(base) == 1);
	assert(base.head.size == HugePageSize);
	assert(isAligned(ptr0, Quantum));

	auto ptr1 = base.alloc(3, 1);
	assert(getBlockCount(base) == 1);
	assert(base.head.size == HugePageSize);
	assert(isAligned(ptr1, Quantum));

	// Check large alignment.
	auto ptr3 = base.alloc(HugePageSize, HugePageSize);
	assert(getBlockCount(base) == 2);
	assert(base.head.size == 2 * HugePageSize);
	assert(isAligned(ptr3, HugePageSize));

	// Check that the block we allocate grow exponentially.
	auto ptr4 = base.alloc(HugePageSize, HugePageSize);
	assert(getBlockCount(base) == 3);
	assert(base.head.size == 3 * HugePageSize);
	assert(isAligned(ptr4, HugePageSize));

	// Reuse existing blocks.
	auto ptr5 = base.alloc(HugePageSize / 2, 1);
	assert(getBlockCount(base) == 3);
	assert(isAligned(ptr5, Quantum));

	auto ptr6 = base.alloc(HugePageSize / 2, 1);
	assert(getBlockCount(base) == 3);
	assert(isAligned(ptr6, Quantum));
}
