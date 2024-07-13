module dmd.gc;

import d.gc.tcache;
import d.gc.spec;
import d.gc.slab;

extern(C):

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
bool __sd_gc_fetch_alloc_info(void* ptr, void** base, size_t* size, PageDescriptor* pd, BlkAttr* flags) {
    *pd = threadCache.maybeGetPageDescriptor(ptr);
    auto e = pd.extent;
    *flags = BlkAttr.init;
    if (e) {
        if (!pd.containsPointers) {
            *flags |= BlkAttr.NO_SCAN;
        }

        if (pd.isSlab()) {
            auto si = SlabAllocInfo(pd, ptr);
            *base = cast(void*) si.address;

            if(si.hasMetadata) {
                *flags |= BlkAttr.APPENDABLE;
                if(si.hasFinalizer) {
                    *flags |= BlkAttr.FINALIZE;
                }
            }
            *size = si.capacity;
        } else {
            // large blocks are always appendable.
            *flags |= BlkAttr.APPENDABLE;

            if(e.finalizer) {
                *flags |= BlkAttr.FINALIZE;
            }

            auto e = pd.extent;
            *base = e.address;

            *size = e.size;
        }
        return true;
    }
    return false; 
}

// only for large blocks. For slots, the other side will figure it out.
bool __sd_gc_set_array_used(void* ptr, PageDescriptor pd, size_t newUsed, size_t existingUsed) {
    auto e = pd.extent;
    if (!e) {
        return false;
    }

    if(pd.isSlab()) {

    } else {
    }
}
