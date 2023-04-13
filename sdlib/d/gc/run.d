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
