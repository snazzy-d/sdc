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
		
		// XXX: use extract or something.
		auto run = freeRunTree.bestfit(cast(RunDesc*) runBinID);
		if (run !is null) {
			freeRunTree.remove(run);
		}
		
		if (run is null) {
			auto c = allocateChunk();
			if (c is null) {
				// XXX: In the multithreaded version, we should
				// retry reuse as one run can have been freed
				// while we tried to allocate the chunk.
				return null;
			}
			
			run = &c.runs[0];
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
		
		// XXX: use extract or something.
		auto run = freeRunTree.bestfit(cast(RunDesc*) binID);
		if (run !is null) {
			freeRunTree.remove(run);
		}
		
		if (run is null) {
			auto c = allocateChunk();
			if (c is null) {
				// XXX: In the multithreaded version, we should
				// retry reuse as one run can have been freed
				// while we tried to allocate the chunk.
				return null;
			}
			
			run = &c.runs[0];
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
		
		// XXX: Use Extent.sizeof
		import d.gc.extent;
		auto e = cast(Extent*) allocSmall(40);
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
	
	/**
	 * Chunk allocation facilities.
	 */
	Chunk* allocateChunk() {
		auto c = Chunk.allocate(&this);
		if (c is null) {
			return null;
		}
		
		assert(c.header.arena is &this);
		// assert(c.header.addr is c);
		
		return c;
	}
}

