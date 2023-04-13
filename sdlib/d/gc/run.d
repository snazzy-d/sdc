module d.gc.run;

struct RunDesc {
	import d.gc.rbtree;
	Node!RunDesc rbnode;

	@property
	auto chunk() {
		import d.gc.chunk, d.gc.spec;
		return cast(Chunk*) ((cast(size_t) &this) & ~ChunkAlignMask);
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
	assert(rBinID == getSizeClass(rsize + 1) - 1);

	auto l = cast(size_t) lhs;
	int lBinID;

	import d.gc.spec;
	if (l & ~PageMask) {
		lBinID = lhs.chunk.pages[lhs.runID].binID;

		auto lsize = lhs.chunk.pages[lhs.runID].size;
		assert(lBinID == getSizeClass(lsize + 1) - 1);
	} else {
		lhs = null;
		lBinID = cast(int) (l & PageMask);
	}

	return (lBinID == rBinID) ? addrRunCmp(lhs, rhs) : lBinID - rBinID;
}
