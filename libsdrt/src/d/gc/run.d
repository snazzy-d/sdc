module d.gc.run;

struct RunDesc {
	import d.gc.rbtree;
	Node!RunDesc node;
	
	// TODO: anonymous enum.
	union U {
		DirtyRunMisc dirty;
		SmallRunMisc small;
	}
	
	U misc;
	
	@property
	ref DirtyRunMisc dirty() {
		// FIXME: in contract
		auto pd = chunk.pages[runID];
		assert(pd.free, "Expected free run");
		assert(pd.dirty, "Expected dirty run");
		
		return misc.dirty;
	}
	
	@property
	ref SmallRunMisc small() {
		// FIXME: in contract
		auto pd = chunk.pages[runID];
		assert(pd.allocated, "Expected allocated run");
		assert(pd.offset == 0, "Invalid run");
		assert(pd.small, "Expected small run");
		
		return misc.small;
	}
	
	@property
	auto chunk() {
		import d.gc.chunk, d.gc.spec;
		return cast(Chunk*) ((cast(size_t) &this) & ~AlignMask);
	}
	
	@property
	uint runID() {
		auto offset = (cast(uint) &this) - (cast(uint) &chunk.runs[0]);
		uint r = offset / RunDesc.sizeof;
		
		// FIXME: out contract
		import d.gc.chunk;
		assert(r < DataPages);
		return r;
	}
}

ptrdiff_t addrRunCmp(RunDesc* lhs, RunDesc* rhs) {
	auto l = cast(size_t) lhs;
	auto r = cast(size_t) rhs;
	
	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

ptrdiff_t sizeAddrRunCmp(RunDesc* lhs, RunDesc* rhs) {
	import d.gc.sizeclass;
	int rBinID = rhs.chunk.pages[rhs.runID].binID;
	
	auto rsize = rhs.chunk.pages[rhs.runID].size;
	assert(rBinID == getBinID(rsize + 1) - 1);
	
	auto l = cast(size_t) lhs;
	int lBinID;
	
	import d.gc.spec;
	if (l & ~PageMask) {
		lBinID = lhs.chunk.pages[lhs.runID].binID;
		
		auto lsize = lhs.chunk.pages[lhs.runID].size;
		assert(lBinID == getBinID(lsize + 1) - 1);
	} else {
		lhs = null;
		lBinID = cast(int) (l & PageMask);
	}
	
	return (lBinID == rBinID)
		? addrRunCmp(lhs, rhs)
		: lBinID - rBinID;
}

private:

struct DirtyRunMisc {
	RunDesc* next;
	RunDesc* prev;
}

struct SmallRunMisc {
	ubyte binID;
	ushort freeSlots;
	
	ushort bitmapIndex;
	
	ushort header;
	uint[16] bitmap;
	
	uint allocate() {
		// TODO: in contracts.
		assert(freeSlots > 0);
		
		// TODO: Use bsr when available.
		uint hindex;
		for (hindex = 0; hindex < 16; hindex++) {
			if (header & 1 << hindex) {
				break;
			}
		}
		
		assert(hindex < 16, "Cannot allocate from that run");
		
		// TODO: Use bsr when available.
		for (uint bindex = 0; bindex < 32; bindex++) {
			if (bitmap[hindex] & (1 << bindex)) {
				// Use xor so we don't need to invert bits.
				// It is ok as we assert the bit is unset before.
				bitmap[hindex] ^= (1 << bindex);
				
				// If we unset all bits, unset header.
				if (bitmap[hindex] == 0) {
					header ^= cast(ushort) (1 << hindex);
				}
				
				freeSlots--;
				return hindex * 32 + bindex;
			}
		}
		
		assert(0, "Invalid bitmap");
	}
	
	bool isFree(uint bit) const {
		// TODO: in contract.
		assert(bit < 512);
		
		auto hindex = bit / 32;
		auto bindex = bit % 32;
		
		// TODO: in contract.
		assert(hindex < 16);
		
		return !!(bitmap[hindex] & (1 << bindex));
	}
	
	void free(uint bit) {
		// TODO: in contract.
		assert(bit < 512);
		assert(!isFree(bit), "Already freed");
		
		auto hindex = bit / 32;
		auto bindex = bit % 32;
		
		// TODO: in contract.
		assert(hindex < 16);
		
		freeSlots++;
		header |= cast(ushort) (1 << hindex);
		bitmap[hindex] |= (1 << bindex);
	}
}

