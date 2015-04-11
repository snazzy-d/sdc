module d.gc.arena;

Arena tl;

extern(C) void* _tl_gc_alloc(size_t size) {
	return tl.alloc(size);
}

extern(C) void _tl_gc_free(void* ptr) {
	tl.free(ptr);
}

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
	ulong* chunkKeys;
	uint chunkCount;
	
	// Metadatas for the chunk set.
	ubyte lgChunkSetSize;
	ubyte chunkMaxProbe;
	
	import d.gc.bin, d.gc.sizeclass;
	Bin[ClassCount.Small] bins;
	
	void* alloc(size_t size) {
		if (size < SizeClass.Small) {
			return allocSmall(size);
		}
		
		if (size < SizeClass.Large) {
			return allocLarge(size);
		}
		
		return allocHuge(size);
	}
	
	void free(void* ptr) {
		import d.gc.spec;
		auto c = cast(Chunk*) ((cast(size_t) ptr) & ~AlignMask);
		
		// XXX: type promotion is fucked.
		auto vc = cast(void*) c;
		
		// XXX: assert that we own that chunk.
		if (vc !is ptr) {
			freeInChunk(ptr, c);
		} else {
			freeHuge(ptr);
		}
	}
	
private:
	/**
	 * Small allocation facilities.
	 */
	void* allocSmall(size_t size) {
		// TODO: in contracts
		assert(size < SizeClass.Small);
		
		auto binID = getBinID(size);
		assert(binID < ClassCount.Small);
		
		// TODO: Precompute bininfos and read from there.
		size = getAllocSize(size);
		
		auto run = findSmallRun(binID);
		if (run is null) {
			return null;
		}
		
		auto index = run.misc.small.allocate();
		auto base = cast(void*) &run.chunk.datas[run.index];
		
		return base + size * index;
	}
	
	RunDesc* findSmallRun(ubyte binID) {
		// XXX: in contract.
		assert(binID < ClassCount.Small);
		
		auto run = bins[binID].current;
		if (run !is null && run.misc.small.freeSlots != 0) {
			return run;
		}
		
		// XXX: use extract or something.
		run = bins[binID].runTree.bestfit(null);
		if (run !is null) {
			bins[binID].runTree.remove(run);
		} else {
			run = allocateSmallRun(binID);
		}
		
		return bins[binID].current = run;
	}
	
	RunDesc* allocateSmallRun(ubyte binID) {
		// XXX: in contract.
		assert(binID < ClassCount.Small);
		
		import d.gc.spec;
		uint needPages = binInfos[binID].needPages;
		auto runBinID = getBinID(needPages << LgPageSize);
		
		auto run = extractFreeRun(runBinID);
		if (run is null) {
			return null;
		}
		
		auto c = run.chunk;
		auto i = run.index;
		
		auto rem = c.splitSmallRun(i, binID);
		if (rem) {
			freeRunTree.insert(&c.runs[rem]);
		}
		
		return run;
	}
	
	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(size_t size) {
		// TODO: in contracts
		assert(size >= SizeClass.Small && size < SizeClass.Large);
		
		auto run = allocateLargeRun(getAllocSize(size));
		if (run is null) {
			return null;
		}
		
		return cast(void*) &run.chunk.datas[run.index];
	}
	
	RunDesc* allocateLargeRun(size_t size) {
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
		
		auto rem = c.splitLargeRun(size, i, binID);
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
		return c.pages[0].allocated
			? extractFreeRun(binID)
			: &c.runs[0];
	}
	
	/**
	 * Free in chunk.
	 */
	void freeInChunk(void* ptr, Chunk* c) {
		auto offset = (cast(uint) ptr) - (cast(uint) &c.datas[0]);
		
		import d.gc.spec;
		auto runID = offset >> LgPageSize;
		auto pd = c.pages[runID];
		assert(pd.allocated);
		
		runID -= pd.offset;
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
		run.misc.small.free(index);
		
		auto freeSlots = run.misc.small.freeSlots;
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
		
		// Sanity check: no intern pointer.
		auto base = cast(void*) &c.datas[runID];
		assert(ptr is base);
		
		auto largeBinID = binID - ClassCount.Small;
		auto shift = largeBinID / 4;
		auto bits = 4 + largeBinID % 4;
		
		freeRun(c, runID, bits << shift);
	}
	
	void freeRun(Chunk* c, uint runID, uint pages) {
		// XXX: in contract.
		auto pd = c.pages[runID];
		assert(pd.allocated && pd.offset == 0);
		
		if (runID > 0) {
			auto previous = c.pages[runID - 1];
			if (!previous.allocated) {
				runID -= previous.offset;
				pages += previous.offset;
				
				freeRunTree.remove(&c.runs[runID]);
			}
		}
		
		if (runID + pages < DataPages) {
			auto nextID = runID + pages;
			auto next = c.pages[nextID];
			assert(!next.allocated || next.offset == 0);
			
			if (!next.allocated) {
				pages += next.offset;
				
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
			pd.zeroed,
			pd.dirty,
			runBinID,
			pages,
		);
		
		c.pages[runID] = d;
		c.pages[runID + pages - 1] = d;
		
		freeRunTree.insert(&c.runs[runID]);
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
	
	void freeHuge(void* ptr) {
		// XXX: in contracts
		import d.gc.spec;
		auto vc = cast(void*) ((cast(size_t) ptr) & ~AlignMask);
		assert(vc is ptr);
		
		if (ptr is null) {
			// free(null) is valid, we want to handle it properly.
			// XXX: return; is not supported.
			goto Exit;
		}
		{
		Extent test;
		test.addr = ptr;
		
		// XXX: extract
		auto e = hugeTree.find(&test);
		assert(e !is null);
		
		import d.gc.mman;
		pages_unmap(e.addr, e.size);
		
		hugeTree.remove(e);
		free(e);
		}
		Exit:
	}
	
	/**
	 * Chunk allocation facilities.
	 */
	Chunk* allocateChunk() {
		// If we have a spare chunk, use that.
		if (spare !is null) {
			auto c = spare;
			spare = null;
			return c;
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
		if (registerChunk(c)) {
			c.free();
			c = null;
		}
		
		spare = null;
		return c;
	}
	
	bool registerChunk(Chunk* c) {
		// We resize if the set if 7/8 full.
		auto limitSize = (7UL << lgChunkSetSize) / 8;
		if (limitSize <= chunkCount) {
			auto oldChunkKeys = chunkKeys;
			auto oldChunkSetSize = 1UL << lgChunkSetSize;
			
			lgChunkSetSize++;
			assert(lgChunkSetSize <= 32);
			
			// FIXME: Use calloc.
			import d.gc.spec;
			auto newChunkKeys = cast(ulong*) alloc(ulong.sizeof << lgChunkSetSize);
			assert(oldChunkKeys is chunkKeys);
			
			if (newChunkKeys is null) {
				return true;
			}
			
			// XXX: Using calloc would remove the need to zero this.
			for (uint i = 0; i < oldChunkSetSize * 2; i++) {
				newChunkKeys[i] = 0;
			}
			
			chunkMaxProbe = 0;
			chunkKeys = newChunkKeys;
			auto rem = chunkCount;
			
			for(uint i = 0; rem != 0; i++) {
				assert(i < oldChunkSetSize);
				
				auto k = oldChunkKeys[i];
				if (k == 0) {
					continue;
				}
				
				insertKeyInSet(k);
				rem--;
			}
			
			free(oldChunkKeys);
		}
		
		import d.gc.spec;
		auto k = (cast(size_t) c) >> LgChunkSize;
		
		chunkCount++;
		insertKeyInSet(k);
		
		return false;
	}
	
	void insertKeyInSet(ulong k) {
		auto setSize = 1 << lgChunkSetSize;
		auto setMask = setSize - 1;
		
		auto c = (cast(uint) k) & setMask;
		
		auto i = c;
		ubyte d = 0;
		while(chunkKeys[i] != 0) {
			auto e = chunkKeys[i];
			auto ce = (cast(uint) e) & setMask;
			
			// Robin hood haching.
			if (d > (i - ce)) {
				chunkKeys[i] = k;
				k = e;
				c = ce;
				
				if (d > chunkMaxProbe) {
					chunkMaxProbe = d;
				}
			}
			
			i = ((i + 1) & setMask);
			d = cast(ubyte) (i - c);
		}
		
		chunkKeys[i] = k;
		if (d > chunkMaxProbe) {
			chunkMaxProbe = d;
		}
	}
}

