module d.gc.base;

import d.gc.spec;
import d.gc.util;

shared Base gBase;

/**
 * Bump the pointer style allocator.
 *
 * It never deallocates, except on destruction.
 * It serves as a base allocator for address space.
 */
struct Base {
private:
	import d.sync.mutex;
	Mutex mutex;

	ubyte currentGeneration;

	// The slice of memory we have to allocate from.
	void* nextMetadataAddr;
	size_t availableMetadatSlots;

	// Linked list of all the blocks.
	Block* head;

	// Free list of block headers to be reserved.
	Block* blockFreeList;

public:
	void clear() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Base*) &this).clearImpl();
	}

	static assert(LgAddressSpace <= 48, "Address space too large!");

	struct Slot {
	private:
		ulong data;

		this(void* ptr, ubyte generation) {
			data = cast(size_t) ptr;
			data |= ulong(generation) << 56;
		}

	public:
		@property
		void* address() {
			return cast(void*) (data & AddressMask);
		}

		@property
		ubyte generation() {
			return data >> 56;
		}
	}

	Slot allocSlot() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Base*) &this).allocSlotImpl();
	}

	void* reserveAddressSpace(size_t size) shared {
		// Bump the alignement to huge page size if apropriate.
		auto alignment =
			isAligned(size, HugePageSize) ? HugePageSize : PageSize;

		size = alignUp(size, alignment);
		return reserveAddressSpace(size, alignment);
	}

	void* reserveAddressSpace(size_t size, size_t alignment) shared {
		assert(alignment >= PageSize && isPow2(alignment),
		       "Invalid alignment!");
		assert(size > 0 && isAligned(size, PageSize), "Invalid size!");

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Base*) &this).reserveAddressSpaceImpl(size, alignment);
	}

private:
	void clearImpl() {
		assert(mutex.isHeld(), "Mutex not held!");

		head.clearAll();
		head = null;
		blockFreeList = null;
	}

	Slot allocSlotImpl() {
		assert(mutex.isHeld(), "Mutex not held!");

		if (!refillMetadataSpace()) {
			return Slot(null, 0);
		}

		assert(availableMetadatSlots > 0, "No Metadata slot available!");
		assert(isAligned(nextMetadataAddr, ExtentAlign),
		       "Invalid nextMetadataAddr alignment!");

		scope(success) {
			nextMetadataAddr += ExtentSize;
			availableMetadatSlots -= 1;
		}

		return Slot(nextMetadataAddr, currentGeneration);
	}

	void* reserveAddressSpaceImpl(size_t size, size_t alignment) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto block = getOrAllocateBlock();
		if (block is null) {
			return null;
		}

		import d.gc.pages;
		auto ptr = pages_map(null, size, alignment);
		if (ptr is null) {
			freeBlockImpl(block);
			return null;
		}

		registerBlock(block, ptr, size);
		return ptr;
	}

	/**
	 * Block management.
	 */
	Block* allocBlock() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Base*) &this).getOrAllocateBlock();
	}

	void freeBlock(Block* block) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Base*) &this).freeBlockImpl(block);
	}

	auto freeBlockImpl(Block* block) {
		assert(mutex.isHeld(), "Mutex not held!");

		block.next = blockFreeList;
		blockFreeList = block;
	}

	void registerBlock(Block* block, void* ptr, size_t size) {
		assert(mutex.isHeld(), "Mutex not held!");

		block.addr = ptr;
		block.size = HugePageSize;
		block.next = head;

		head = block;
	}

	auto getOrAllocateBlock() {
		assert(mutex.isHeld(), "Mutex not held!");

		auto block = getBlockInFrelist();
		if (block !is null) {
			return block;
		}

		if (!refillMetadataSpace()) {
			return null;
		}

		block = getBlockInFrelist();
		if (block !is null) {
			return block;
		}

		assert(availableMetadatSlots > 0, "No Metadata slot available!");
		assert(isAligned(nextMetadataAddr, ExtentAlign),
		       "Invalid nextMetadataAddr alignment!");
		assert(blockFreeList is null, "There are blocks in the freelist!");

		enum BlockPerExtent = ExtentSize / alignUp(Block.sizeof, Quantum);
		static assert(BlockPerExtent == 5, "For documentation purposes.");

		auto ret = cast(Block*) nextMetadataAddr;
		nextMetadataAddr += ExtentSize;
		availableMetadatSlots -= 1;

		foreach (i; 2 .. BlockPerExtent) {
			ret[i - 1].next = &ret[i];
			ret[i].next = null;
		}

		if (BlockPerExtent > 1) {
			blockFreeList = &ret[1];
		}

		return ret;
	}

	Block* getBlockInFrelist() {
		assert(mutex.isHeld(), "Mutex not held!");

		if (blockFreeList is null) {
			return null;
		}

		auto ret = blockFreeList;
		blockFreeList = blockFreeList.next;
		return ret;
	}

	bool refillMetadataSpace() {
		assert(mutex.isHeld(), "Mutex not held!");

		if (availableMetadatSlots > 0) {
			return true;
		}

		// Allocate exponentially more space for metadata.
		auto shift = currentGeneration++;
		auto size = HugePageSize << shift;

		import d.gc.pages;
		auto ptr = pages_map(null, size, size);
		if (ptr is null) {
			return false;
		}

		enum SlotPerHugePage = HugePageSize / ExtentSize;
		nextMetadataAddr = ptr;
		availableMetadatSlots = SlotPerHugePage << shift;

		// We expect this allocation to always succeed as we just
		// reserved a ton of address space.
		auto block = getOrAllocateBlock();
		assert(block !is null, "Failed to allocate a block!");

		registerBlock(block, ptr, size);
		return true;
	}
}

private:
static assert(Block.sizeof <= ExtentSize, "Block got too large!");

struct Block {
	void* addr;
	size_t size;

	Block* next;

	void clearAll() {
		auto next = &this;
		while (next !is null) {
			auto block = next;
			next = block.next;

			import d.gc.pages;
			pages_unmap(block.addr, block.size);
		}
	}
}

unittest base {
	shared Base base;
	scope(exit) base.clear();

	// We can allocate blocks from mdbase.
	auto b0 = base.allocBlock();
	auto b1 = base.allocBlock();
	assert(b0 !is b1);
	assert(base.availableMetadatSlots == 16383);

	// We get the same block recycled.
	base.freeBlock(b0);
	base.freeBlock(b1);
	assert(base.allocBlock() is b1);
	assert(base.allocBlock() is b0);
	assert(base.availableMetadatSlots == 16383);

	// Now allocate slots.
	auto s0 = base.allocSlot();
	auto s1 = base.allocSlot();
	assert(s0.address !is s1.address);
	assert(s0.generation == s1.generation);
	assert(base.availableMetadatSlots == 16381);
}
