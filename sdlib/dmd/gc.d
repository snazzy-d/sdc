module dmd.gc;

import d.gc.tcache;
import d.gc.spec;
import d.gc.slab;

extern(C):

/**
 * Druntime hooks
 */

// copied from druntime, to see what the bits mean.
enum BlkAttr : uint {
	NONE = 0b0000_0000, /// No attributes set.
	FINALIZE = 0b0000_0001, /// Finalize the data in this block on collect.
	NO_SCAN = 0b0000_0010, /// Do not scan through this block on collect.
	NO_MOVE = 0b0000_0100, /// Do not move this memory block on collect.
	/**
      This block contains the info to allow appending.

      This can be used to manually allocate arrays. Initial slice size is 0.

      Note: The slice's usable size will not match the block size. Use
      $(LREF capacity) to retrieve actual usable capacity.

      Example:
      ----
    // Allocate the underlying array.
    int*  pToArray = cast(int*)GC.malloc(10 * int.sizeof, GC.BlkAttr.NO_SCAN | GC.BlkAttr.APPENDABLE);
    // Bind a slice. Check the slice has capacity information.
    int[] slice = pToArray[0 .. 0];
    assert(capacity(slice) > 0);
    // Appending to the slice will not relocate it.
    slice.length = 5;
    slice ~= 1;
    assert(slice.ptr == p);
    ----
     */
	APPENDABLE = 0b0000_1000,

	/**
     * This block is guaranteed to have a pointer to its base while it is
     * alive.  Interior pointers can be safely ignored.  This attribute is
     * useful for eliminating false pointers in very large data structures
     * and is only implemented for data structures at least a page in size.
     */
	NO_INTERIOR = 0b0001_0000,

	// The block has a finalizer for (an array of) structs.
	STRUCTFINAL = 0b0010_0000,
}

struct BlkInfo {
	void* base;
	size_t size;
	uint attr;
}

// TODO: handle finalizer
// BlkInfo __sd_gc_druntime_qalloc(size_t size, uint bits, void *finalizer)
void __sd_gc_druntime_qalloc(BlkInfo* result, size_t size, uint bits,
                             void* finalizer) {
	//import core.stdc.stdio;
	//printf("In sdc qalloc, size is %d\n", cast(int)size);
	bool hasPointers = (bits & BlkAttr.NO_SCAN) == 0;
	// note, we don't use sdc's appending mechanism for now, but we want to
	// keep the bit relevant
	bool appendable = (bits & BlkAttr.APPENDABLE) != 0;

	//BlkInfo result;

	// all the rest are ignored for now.
	if (appendable || finalizer !is null) {
		import core.stdc.stdio;
		//printf("In sdc qalloc, with finalizer or appendable: %p\n", finalizer);
		result.base = threadCache
			.allocAppendable(size, hasPointers, hasPointers, finalizer);
		//printf("allocated address %p\n", result.base);
	} else {
		result.base = threadCache.alloc(size, hasPointers, hasPointers);
	}

	// printf("returning pointer %p\n", result.base);
	result.size = size;

	// note, we may not need this code, and probably shouldn't use it.
	/*if (result.base) {
		if (appendable) {
			// figure out the capacity, set it to max, and then use that size
			// for the caller.
			auto cap = threadCache.getCapacity(result.base[0 .. size]);
			if (cap == 0) {
				result.size = size;
			} else {
				assert(threadCache.extend(result.base[0 .. size], cap - size));
				result.size = cap;
			}
		} else {
			// no good mechanism to look this up, so wing it
			auto pd = threadCache.getPageDescriptor(result.base);
			if (pd.isSlab()) {
				auto si = SlabAllocInfo(pd, result.base);
				result.size = si.usedCapacity;
			} else {
				auto e = pd.extent;
				result.size = e.usedCapacity;
			}
		}
	}*/

	result.attr =
		bits & (BlkAttr.APPENDABLE | BlkAttr.NO_SCAN | BlkAttr.FINALIZE);
	//return result;
}

BlkInfo __sd_gc_druntime_allocInfo(void* ptr) {
	// get the information about the pointer
	BlkInfo result;
	auto pd = threadCache.getPageDescriptor(ptr);
	if (pd.isSlab()) {
		auto si = SlabAllocInfo(pd, ptr);
		result.base = cast(void*) si.address;
		result.size = si.usedCapacity;
		if (si.hasMetadata) {
			result.attr |= BlkAttr.APPENDABLE;
		}
	} else {
		auto e = pd.extent;
		result.base = e.address;
		result.size = e.usedCapacity;
		// all large allocs are appendable
		result.attr |= BlkAttr.APPENDABLE;
	}

	if (!pd.containsPointers) {
		result.attr |= BlkAttr.NO_SCAN;
	}

	return result;
}
