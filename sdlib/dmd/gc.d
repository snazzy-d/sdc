module dmd.gc;

import d.gc.tcache;
import d.gc.spec;
import d.gc.slab;
import d.gc.emap;

extern(C):

void __sd_gc_init() {
	import d.gc.thread;
	createProcess();
}

// Some of the bits from druntime.
enum BlkAttr : uint {
	FINALIZE = 0b0000_0001,
	NO_SCAN = 0b0000_0010,
	APPENDABLE = 0b0000_1000
}

// ptr: the pointer to query
// base: => the true base address of the block
// size: => the full usable size of the block
// pd: => the page descriptor (used internally later)
// flags: => what the flags of the block are
//
bool __sd_gc_fetch_alloc_info(void* ptr, void** base, size_t* size,
                              PageDescriptor* pd, BlkAttr* flags) {
	*pd = threadCache.maybeGetPageDescriptor(ptr);
	auto e = pd.extent;
	*flags = cast(BlkAttr) 0;
	if (!e) {
		return false;
	}

	if (!pd.containsPointers) {
		*flags |= BlkAttr.NO_SCAN;
	}

	if (pd.isSlab()) {
		auto si = SlabAllocInfo(*pd, ptr);
		*base = cast(void*) si.address;

		if (si.hasMetadata) {
			*flags |= BlkAttr.APPENDABLE;
			if (si.finalizer) {
				*flags |= BlkAttr.FINALIZE;
			}
		}

		*size = si.slotCapacity;
	} else {
		// Large blocks are always appendable.
		*flags |= BlkAttr.APPENDABLE;

		if (e.finalizer) {
			*flags |= BlkAttr.FINALIZE;
		}

		auto e = pd.extent;
		*base = e.address;

		*size = e.size;
	}

	return true;
}

size_t __sd_gc_get_array_used(void* ptr, PageDescriptor pd) {
	auto e = pd.extent;
	if (!e) {
		return 0;
	}

	if (pd.isSlab()) {
		auto si = SlabAllocInfo(pd, ptr);
		return si.usedCapacity;
	} else {
		return e.usedCapacity;
	}
}

// TODO: this should only do large blocks, and let the druntime side do slabs.
bool __sd_gc_set_array_used(void* ptr, PageDescriptor pd, size_t newUsed,
                            size_t existingUsed) {
	auto e = pd.extent;
	if (!e) {
		return false;
	}

	if (pd.isSlab()) {
		auto si = SlabAllocInfo(pd, ptr);
		if (existingUsed < size_t.max && existingUsed != si.usedCapacity) {
			// The existing capacity doesn't match.
			return false;
		}

		return si.setUsedCapacity(newUsed);
	} else {
		if (existingUsed < size_t.max && existingUsed != e.usedCapacity) {
			// The existing capacity doesn't match.
			return false;
		}

		e.setUsedCapacity(newUsed);
	}

	return true;
}

void* __sd_gc_alloc_no_pointers(size_t size) {
	return threadCache.alloc(size, false, false);
}

void* __sd_gc_alloc_finalizer_no_pointers(size_t size, void* finalizer) {
	return threadCache.allocAppendable(size, false, false, finalizer);
}

size_t __sd_gc_resize(void* ptr, size_t request) {
	return threadCache.resize(ptr, request);
}
