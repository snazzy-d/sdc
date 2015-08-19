module d.gc.arena;

extern(C) void* _tl_gc_alloc(size_t size) {
	return tl.alloc(size);
}

extern(C) void _tl_gc_free(void* ptr) {
	tl.free(ptr);
}

extern(C) void* _tl_gc_realloc(void* ptr, size_t size) {
	return tl.realloc(ptr, size);
}

extern(C) void _tl_gc_set_stack_bottom(const void* bottom) {
	tl.stackBottom = bottom;
}

extern(C) void _tl_gc_add_roots(const void[] range) {
	tl.addRoots(range);
}

Arena tl;

struct Arena {
	// Spare chunk to avoid churning too much.
	import d.gc.chunk;
	Chunk* spare;
	
	// Free runs we can allocate from.
	import d.gc.rbtree, d.gc.run;
	RBTree!(RunDesc, sizeAddrRunCmp) freeRunTree;
	
	// Extent describing huge allocs.
	import d.gc.extent;
	RBTree!(Extent, addrExtentCmp) hugeTree;
	
	// Set of chunks for GC lookup.
	ChunkSet chunkSet;
	
	const void* stackBottom;
	const(void[])[] roots;
	
	import d.gc.bin, d.gc.sizeclass;
	Bin[ClassCount.Small] bins;
	
	void* alloc(size_t size) {
		if (size < SizeClass.Small) {
			return allocSmall(size);
		}
		
		if (size < SizeClass.Large) {
			return allocLarge(size, false);
		}
		
		return allocHuge(size);
	}
	
	void* calloc(size_t size) {
		if (size < SizeClass.Small) {
			auto ret = allocSmall(size);
			memset(ret, 0, size);
			return ret;
		}
		
		if (size < SizeClass.Large) {
			return allocLarge(size, true);
		}
		
		return allocHuge(size);
	}
	
	void free(void* ptr) {
		auto c = findChunk(ptr);
		if (c !is null) {
			freeInChunk(ptr, c);
		} else {
			freeHuge(ptr);
		}
	}
	
	void* realloc(void* ptr, size_t size) {
		if (size == 0) {
			free(ptr);
			return null;
		}
		
		if (ptr is null) {
			return alloc(size);
		}
		
		auto newBinID = getBinID(size);
		
		// TODO: Try in place resize for large/huge.
		auto oldBinID = newBinID;
		
		auto c = findChunk(ptr);
		if (c !is null) {
			oldBinID = c.pages[findRunID(ptr, c)].binID;
		} else {
			oldBinID = getBinID(findHugeExtent(ptr).size);
		}
		
		if (newBinID == oldBinID) {
			return ptr;
		}
		
		auto newPtr = alloc(size);
		if (newPtr is null) {
			return null;
		}
		
		if (newBinID > oldBinID) {
			memcpy(newPtr, ptr, getSizeFromBinID(oldBinID));
		} else {
			memcpy(newPtr, ptr, size);
		}
		
		free(ptr);
		return newPtr;
	}
	
private:
	Chunk* findChunk(void* ptr) {
		import d.gc.spec;
		// TODO: in contracts
		auto c = cast(Chunk*) ((cast(size_t) ptr) & ~AlignMask);
		
		// XXX: type promotion is fucked.
		auto vc = cast(void*) c;
		if (vc is ptr) {
			// Huge alloc, no arena.
			return null;
		}
		
		// This is not a huge alloc, assert we own the arena.
		assert(c.header.arena is &this);
		return c;
	}
	
	uint findRunID(void* ptr, Chunk* c) {
		// TODO: in contracts
		assert(findChunk(ptr) is c);
		
		auto offset = (cast(uint) ptr) - (cast(uint) &c.datas[0]);
		
		import d.gc.spec;
		auto runID = offset >> LgPageSize;
		auto pd = c.pages[runID];
		assert(pd.allocated);
		
		runID -= pd.offset;
		
		pd = c.pages[runID];
		assert(pd.allocated);
		
		return runID;
	}
	
	/**
	 * Small allocation facilities.
	 */
	void* allocSmall(size_t size) {
		// TODO: in contracts
		assert(size < SizeClass.Small);
		
		auto binID = getBinID(size);
		assert(binID < ClassCount.Small);
		
		// Load eagerly as prefetching.
		size = binInfos[binID].size;
		
		auto run = findSmallRun(binID);
		if (run is null) {
			return null;
		}
		
		auto index = run.small.allocate();
		auto base = cast(void*) &run.chunk.datas[run.index];
		
		return base + size * index;
	}
	
	RunDesc* findSmallRun(ubyte binID) {
		// XXX: in contract.
		assert(binID < ClassCount.Small);
		
		auto run = bins[binID].current;
		if (run !is null && run.small.freeSlots != 0) {
			return run;
		}
		
		// This will allow to keep track if metadata are allocated in that bin.
		bins[binID].current = null;
		
		// XXX: use extract or something.
		run = bins[binID].runTree.bestfit(null);
		if (run is null) {
			// We don't have any run that fit, allocate a new one.
			return allocateSmallRun(binID);
		}
		
		bins[binID].runTree.remove(run);
		return bins[binID].current = run;
	}
	
	RunDesc* allocateSmallRun(ubyte binID) {
		// XXX: in contract.
		assert(binID < ClassCount.Small);
		assert(bins[binID].current is null);
		
		import d.gc.spec;
		uint needPages = binInfos[binID].needPages;
		auto runBinID = getBinID(needPages << LgPageSize);
		
		auto run = extractFreeRun(runBinID);
		if (run is null) {
			return null;
		}
		
		// We may have allocated the run we need when allcoating metadata.
		if (bins[binID].current !is null) {
			// In which case we put the free run back in the tree.
			freeRunTree.insert(run);
			
			// And use the metadata run.
			return bins[binID].current;
		}
		
		auto c = run.chunk;
		auto i = run.index;
		
		auto rem = c.splitSmallRun(i, binID);
		if (rem) {
			freeRunTree.insert(&c.runs[rem]);
		}
		
		return bins[binID].current = run;
	}
	
	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(size_t size, bool zero) {
		// TODO: in contracts
		assert(size >= SizeClass.Small && size < SizeClass.Large);
		
		auto run = allocateLargeRun(getAllocSize(size), zero);
		if (run is null) {
			return null;
		}
		
		return cast(void*) &run.chunk.datas[run.index];
	}
	
	RunDesc* allocateLargeRun(size_t size, bool zero) {
		// TODO: in contracts
		assert(size >= SizeClass.Small && size < SizeClass.Large);
		assert(size == getAllocSize(size));
		
		auto binID = getBinID(size);
		assert(binID >= ClassCount.Small && binID < ClassCount.Large);
		
		auto run = extractFreeRun(binID);
		if (run is null) {
			return null;
		}
		
		auto c = run.chunk;
		auto i = run.index;
		
		auto rem = c.splitLargeRun(size, i, binID, zero);
		if (rem) {
			freeRunTree.insert(&c.runs[rem]);
		}
		
		return run;
	}
	
	/**
	 * Extract free run from an existing or newly allocated chunk.
	 * The run will not be present in the freeRunTree.
	 */
	RunDesc* extractFreeRun(ubyte binID) {
		// XXX: use extract or something.
		auto run = freeRunTree.bestfit(cast(RunDesc*) binID);
		if (run !is null) {
			freeRunTree.remove(run);
			return run;
		}
		
		auto c = allocateChunk();
		if (c is null) {
			// XXX: In the multithreaded version, we should
			// retry reuse as one run can have been freed
			// while we tried to allocate the chunk.
			return null;
		}
		
		// In rare cases, we may have allocated metadata
		// in the chunk for bookkeeping.
		if (c.pages[0].allocated) {
			return extractFreeRun(binID);
		}
		
		return &c.runs[0];
	}
	
	/**
	 * Free in chunk.
	 */
	void freeInChunk(void* ptr, Chunk* c) {
		auto runID = findRunID(ptr, c);
		auto pd = c.pages[runID];
		assert(pd.allocated);
		
		if (pd.small) {
			freeSmall(ptr, c, pd.binID, runID);
		} else {
			freeLarge(ptr, c, pd.binID, runID);
		}
	}
	
	void freeSmall(void* ptr, Chunk* c, uint binID, uint runID) {
		// XXX: in contract.
		assert(binID < ClassCount.Small);
		
		auto offset = (cast(uint) ptr) - (cast(uint) &c.datas[runID]);
		
		auto binInfo = binInfos[binID];
		auto size = binInfo.size;
		auto index = offset / size;
		
		// Sanity check: no intern pointer.
		auto base = cast(void*) &c.datas[runID];
		assert(ptr is (base + size * index));
		
		auto run = &c.runs[runID];
		run.small.free(index);
		
		auto freeSlots = run.small.freeSlots;
		if (freeSlots == binInfo.freeSlots) {
			if (run is bins[binID].current) {
				bins[binID].current = null;
			} else if (binInfo.freeSlots > 1) {
				// When we only have one slot in the run,
				// it is never added to the tree.
				bins[binID].runTree.remove(run);
			}
			
			freeRun(c, runID, binInfo.needPages);
		} else if (freeSlots == 1 && run !is bins[binID].current) {
			bins[binID].runTree.insert(run);
		}
	}
	
	void freeLarge(void* ptr, Chunk* c, uint binID, uint runID) {
		// TODO: in contracts
		assert(binID >= ClassCount.Small && binID < ClassCount.Large);
		
		// Sanity check: no interior pointer.
		auto base = cast(void*) &c.datas[runID];
		assert(ptr is base);
		
		import d.gc.spec;
		auto pages = cast(uint) (getSizeFromBinID(binID) >> LgPageSize);
		freeRun(c, runID, pages);
	}
	
	void freeRun(Chunk* c, uint runID, uint pages) {
		// XXX: in contract.
		auto pd = c.pages[runID];
		assert(pd.allocated && pd.offset == 0);
		
		// XXX: find a way to merge dirty and clean free runs.
		if (runID > 0) {
			auto previous = c.pages[runID - 1];
			if (previous.free && previous.dirty) {
				runID -= previous.pages;
				pages += previous.pages;
				
				freeRunTree.remove(&c.runs[runID]);
			}
		}
		
		if (runID + pages < DataPages) {
			auto nextID = runID + pages;
			auto next = c.pages[nextID];
			
			if (next.free && next.dirty) {
				pages += next.pages;
				
				freeRunTree.remove(&c.runs[nextID]);
			}
		}
		
		import d.gc.spec;
		auto runBinID = cast(ubyte) (getBinID((pages << LgPageSize) + 1) - 1);
		
		// If we have remaining free space, keep track of it.
		import d.gc.bin;
		auto d = PageDescriptor(
			false,
			false,
			false,
			true,
			runBinID,
			pages,
		);
		
		c.pages[runID] = d;
		c.pages[runID + pages - 1] = d;
		
		freeRunTree.insert(&c.runs[runID]);
		
		// XXX: remove dirty
	}
	
	/**
	 * Huge alloc/free facilities.
	 */
	void* allocHuge(size_t size) {
		// TODO: in contracts
		assert(size >= SizeClass.Large);
		
		size = getAllocSize(size);
		if (size == 0) {
			// You can't reserve the whole address space.
			return null;
		}
		
		// XXX: Consider having a run for extent.
		// it should provide good locality for huge
		// alloc lookup (for GC scan and huge free).
		import d.gc.extent;
		auto e = cast(Extent*) allocSmall(Extent.sizeof);
		e.arena = &this;
		
		import d.gc.mman, d.gc.spec;
		auto ret = map_chunks(size >> LgChunkSize);
		if (ret is null) {
			free(e);
			return null;
		}
		
		e.addr = ret;
		e.size = size;
		
		hugeTree.insert(e);
		
		return ret;
	}
	
	Extent* findHugeExtent(void* ptr) {
		// XXX: in contracts
		import d.gc.spec;
		assert(((cast(size_t) ptr) & AlignMask) == 0);
		
		Extent test;
		test.addr = ptr;
		
		// XXX: extract
		auto e = hugeTree.find(&test);
		assert(e !is null);
		assert(e.arena is &this);
		
		return e;
	}
	
	void freeHuge(void* ptr) {
		if (ptr is null) {
			// free(null) is valid, we want to handle it properly.
			return;
		}
		
		// XXX: extract
		auto e = findHugeExtent(ptr);
		
		import d.gc.mman;
		pages_unmap(e.addr, e.size);
		
		hugeTree.remove(e);
		free(e);
	}
	
	/**
	 * Chunk allocation facilities.
	 */
	Chunk* allocateChunk() {
		// If we have a spare chunk, use that.
		if (spare !is null) {
			/*
			// FIXME: Only scope(exit) are supported.
			scope(success) spare = null;
			return spare;
			/*/
			auto c = spare;
			spare = null;
			return c;
			//*/
		}
		
		auto c = Chunk.allocate(&this);
		if (c is null) {
			return null;
		}
		
		assert(c.header.arena is &this);
		// assert(c.header.addr is c);
		
		// Adding the chunk as spare so metadata can be allocated
		// from it. For instance, this is useful if the chunk set
		// needs to be resized to register this chunk.
		assert(spare is null);
		spare = c;
		
		// If we failed to register the chunk, free and bail out.
		if (chunkSet.register(c)) {
			c.free();
			c = null;
		}
		
		spare = null;
		return c;
	}
	
	/**
	 * GC facilities
	 */
	void addRoots(const void[] range) {
		// FIXME: Casting to void* is aparently not handled properly :(
		auto ptr = cast(void*) roots.ptr;
		
		// We realloc everytime. It doesn't really matter at this point.
		roots.ptr = cast(const(void[])*) realloc(ptr, (roots.length + 1) * void[].sizeof);
		
		// Using .ptr to bypass bound checking.
		roots.ptr[roots.length] = range;
		
		// Update the range.
		roots = roots.ptr[0 .. roots.length + 1];
	}
}

private:

struct ChunkSet {
	// Set of chunks for GC lookup.
	Chunk** chunks;
	uint chunkCount;
	
	// Metadatas for the chunk set.
	ubyte lgChunkSetSize;
	ubyte chunkMaxProbe;
	
	@property
	Arena* arena() {
		// We can find the arena from this pointer.
		auto chunkSetOffset = cast(size_t) (&(cast(Arena*) null).chunkSet);
		return cast(Arena*) ((cast(size_t) &this) - chunkSetOffset);
	}
	
	import d.gc.chunk;
	bool register(Chunk* c) {
		// We resize if the set is 7/8 full.
		auto limitSize = (7UL << lgChunkSetSize) / 8;
		if (limitSize <= chunkCount) {
			if (increaseSize()) {
				return true;
			}
		}
		
		chunkCount++;
		insert(c);
		
		return false;
	}
	
	void insert(Chunk* c) {
		auto setSize = 1 << lgChunkSetSize;
		auto setMask = setSize - 1;
		
		import d.gc.spec;
		auto k = (cast(size_t) c) >> LgChunkSize;
		auto p = (cast(uint) k) & setMask;
		
		auto i = p;
		ubyte d = 0;
		while(chunks[i] !is null) {
			auto ce = chunks[i];
			auto ke = (cast(size_t) ce) >> LgChunkSize;
			auto pe = (cast(uint) ke) & setMask;
			
			// Robin hood hashing.
			if (d > (i - pe)) {
				chunks[i] = c;
				c = ce;
				k = ke;
				p = pe;
				
				if (d > chunkMaxProbe) {
					chunkMaxProbe = d;
				}
			}
			
			i = ((i + 1) & setMask);
			d = cast(ubyte) (i - p);
		}
		
		chunks[i] = c;
		if (d > chunkMaxProbe) {
			chunkMaxProbe = d;
		}
	}
	
	bool increaseSize() {
		auto oldChunks = chunks;
		auto oldChunkSetSize = 1UL << lgChunkSetSize;
		
		lgChunkSetSize++;
		assert(lgChunkSetSize <= 32);
		
		import d.gc.spec;
		// auto newChunks = cast(Chunk**) arena.calloc(Chunk*.sizeof << lgChunkSetSize);
		auto newChunks = cast(Chunk**) arena.calloc(size_t.sizeof << lgChunkSetSize);
		assert(oldChunks is chunks);
		
		if (newChunks is null) {
			return true;
		}
		
		chunkMaxProbe = 0;
		chunks = newChunks;
		auto rem = chunkCount;
		
		for (uint i = 0; rem != 0; i++) {
			assert(i < oldChunkSetSize);
			
			auto c = oldChunks[i];
			if (c is null) {
				continue;
			}
			
			insert(c);
			rem--;
		}
		
		arena.free(oldChunks);
		return false;
	}
}

