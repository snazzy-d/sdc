module d.gc.arena;

extern(C) void* __sd_gc_tl_malloc(size_t size) {
	return tl.alloc(size);
}

extern(C) void* __sd_gc_tl_array_alloc(size_t size) {
	return __sd_gc_tl_malloc(size);
}

extern(C) void _tl_gc_free(void* ptr) {
	tl.free(ptr);
}

extern(C) void* _tl_gc_realloc(void* ptr, size_t size) {
	return tl.realloc(ptr, size);
}

extern(C) void _tl_gc_set_stack_bottom(const void* bottom) {
	// tl.stackBottom = makeRange(bottom[]).ptr;
	tl.stackBottom = makeRange(bottom[0 .. 0]).ptr;
}

extern(C) void _tl_gc_add_roots(const void[] range) {
	tl.addRoots(range);
}

extern(C) void _tl_gc_collect() {
	tl.collect();
}

Arena tl;

struct Arena {
	import d.sync.mutex;
	shared Mutex chunkMutex;

	// Spare chunk to avoid churning too much.
	import d.gc.chunk;
	Chunk* spare;

	// Free runs we can allocate from.
	import d.gc.rbtree, d.gc.run;
	RBTree!(RunDesc, sizeAddrRunCmp) freeRunTree;

	// Extent describing huge allocs.
	import d.gc.extent;
	ExtentTree hugeTree;
	ExtentTree hugeLookupTree;

	// Set of chunks for GC lookup.
	ChunkSet chunkSet;

	const(void*)* stackBottom;
	const(void*)[][] roots;

	import d.gc.bin, d.gc.sizeclass;
	Bin[ClassCount.Small] bins;

	void* alloc(size_t size) {
		if (size <= SizeClass.Small) {
			return allocSmall(size);
		}

		if (size <= SizeClass.Large) {
			return allocLarge(size, false);
		}

		return allocHuge(size);
	}

	void* calloc(size_t size) {
		if (size <= SizeClass.Small) {
			auto ret = allocSmall(size);
			memset(ret, 0, size);
			return ret;
		}

		if (size <= SizeClass.Large) {
			return allocLarge(size, true);
		}

		return allocHuge(size);
	}

	void free(void* ptr) {
		auto c = findChunk(ptr);
		if (c !is null) {
			// This is not a huge alloc, assert we own the arena.
			assert(c.header.arena is &this);

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
			// This is not a huge alloc, assert we own the arena.
			assert(c.header.arena is &this);
			oldBinID = c.pages[c.getRunID(ptr)].binID;
		} else {
			auto e = extractHugeExtent(ptr);
			assert(e !is null);

			// We need to keep it alive for now.
			hugeTree.insert(e);
			oldBinID = getBinID(e.size);
		}

		if (newBinID == oldBinID) {
			return ptr;
		}

		auto newPtr = alloc(size);
		if (newPtr is null) {
			return null;
		}

		auto cpySize =
			(newBinID > oldBinID) ? getSizeFromBinID(oldBinID) : size;

		memcpy(newPtr, ptr, cpySize);

		free(ptr);
		return newPtr;
	}

private:
	/**
	 * Small allocation facilities.
	 */
	void* allocSmall(size_t size) {
		// TODO: in contracts
		assert(size <= SizeClass.Small);
		if (size == 0) {
			return null;
		}

		auto binID = getBinID(size);
		assert(binID < ClassCount.Small);

		return bins[binID].allocSmall(&this, binID);
	}

	RunDesc* allocateSmallRun(ubyte binID) {
		// XXX: in contract.
		assert(binID < ClassCount.Small);
		assert(bins[binID].current is null);

		import d.gc.spec;
		uint needPages = binInfos[binID].needPages;
		auto runBinID = getBinID(needPages << LgPageSize);

		chunkMutex.lock();
		scope(exit) chunkMutex.unlock();

		auto run = extractFreeRun(runBinID);
		if (run is null) {
			return null;
		}

		auto c = run.chunk;
		auto i = run.runID;

		assert(run.chunk.pages[run.runID].free);
		auto rem = c.splitSmallRun(i, binID);
		if (rem) {
			assert(c.pages[rem].free);
			freeRunTree.insert(&c.runs[rem]);
		}

		return run;
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(size_t size, bool zero) {
		// TODO: in contracts
		assert(size > SizeClass.Small && size <= SizeClass.Large);

		auto run = allocateLargeRun(getAllocSize(size), zero);
		if (run is null) {
			return null;
		}

		return cast(void*) &run.chunk.datas[run.runID];
	}

	RunDesc* allocateLargeRun(size_t size, bool zero) {
		// TODO: in contracts
		assert(size > SizeClass.Small && size <= SizeClass.Large);
		assert(size == getAllocSize(size));

		auto binID = getBinID(size);
		assert(binID >= ClassCount.Small && binID < ClassCount.Large);

		chunkMutex.lock();
		scope(exit) chunkMutex.unlock();

		auto run = extractFreeRun(binID);
		if (run is null) {
			return null;
		}

		auto c = run.chunk;
		auto i = run.runID;

		auto rem = c.splitLargeRun(size, i, binID, zero);
		if (rem) {
			assert(c.pages[rem].free);
			freeRunTree.insert(&c.runs[rem]);
		}

		return run;
	}

	/**
	 * Extract free run from an existing or newly allocated chunk.
	 * The run will not be present in the freeRunTree.
	 */
	RunDesc* extractFreeRun(ubyte binID) {
		// FIXME: in contract.
		assert(chunkMutex.isHeld(), "Mutex not held!");

		while (true) {
			// XXX: use extract or something.
			auto run = freeRunTree.bestfit(cast(RunDesc*) binID);
			if (run !is null) {
				freeRunTree.remove(run);
				return run;
			}

			if (spare !is null) {
				// If we have a spare chunk, use that.
				assert(!spare.pages[0].allocated, "Spare Chunk is not clean!");
				scope(success) spare = null;
				return &spare.runs[0];
			}

			auto c = Chunk.allocate(&this);
			if (c is null) {
				// XXX: In the multithreaded version, we should
				// retry reuse as one run can have been freed
				// while we tried to allocate the chunk.
				return null;
			}

			assert(c.header.arena is &this);
			assert(c.header.addr is cast(void*) c);

			// Adding the chunk as spare so metadata can be allocated
			// from it. For instance, this is useful if the chunk set
			// needs to be resized to register this chunk.
			assert(spare is null);
			spare = c;

			// Maintaining the chunk set might require allocation,
			// so we release the lock.
			chunkMutex.unlock();
			scope(exit) chunkMutex.lock();

			// If we failed to register the chunk, free and bail out.
			if (chunkSet.register(c)) {
				c.free();
				return null;
			}

			// Because we released the mutex, all bets are off,
			// so we have to start again from the begining.
			continue;
		}

		// FIXME: Unsure control flow analysis detects this.
		assert(0, "Unreachable.");
	}

	/**
	 * Free in chunk.
	 */
	void freeInChunk(void* ptr, Chunk* c) {
		auto runID = c.getRunID(ptr);
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
		auto size = binInfo.itemSize;
		auto index = offset / size;

		// Sanity check: no intern pointer.
		auto base = cast(void*) &c.datas[runID];
		assert(ptr is (base + size * index));

		bins[binID].mutex.lock();
		scope(exit) bins[binID].mutex.unlock();

		auto run = &c.runs[runID];
		run.small.free(index);

		auto freeSlots = run.small.freeSlots;
		if (freeSlots == binInfo.slots) {
			if (run is bins[binID].current) {
				bins[binID].current = null;
			} else if (binInfo.slots > 1) {
				// When we only have one slot in the run,
				// it is never added to the tree.
				bins[binID].runTree.remove(run);
			}

			bins[binID].mutex.unlock();
			scope(exit) bins[binID].mutex.lock();

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
		assert(pages > 0);

		chunkMutex.lock();
		scope(exit) chunkMutex.unlock();

		// XXX: find a way to merge dirty and clean free runs.
		if (runID > 0) {
			auto previous = c.pages[runID - 1];
			if (previous.free && previous.dirty) {
				runID -= previous.pages;
				pages += previous.pages;

				assert(c.pages[runID].free);
				freeRunTree.remove(&c.runs[runID]);
			}
		}

		if (runID + pages < DataPages) {
			auto nextID = runID + pages;
			auto next = c.pages[nextID];

			if (next.free && next.dirty) {
				pages += next.pages;

				assert(c.pages[nextID].free);
				freeRunTree.remove(&c.runs[nextID]);
			}
		}

		import d.gc.spec;
		auto runBinID = cast(ubyte) (getBinID((pages << LgPageSize) + 1) - 1);

		// If we have remaining free space, keep track of it.
		import d.gc.bin;
		auto d = PageDescriptor(false, false, false, true, runBinID, pages);

		c.pages[runID] = d;
		c.pages[runID + pages - 1] = d;

		assert(c.pages[runID].free);
		freeRunTree.insert(&c.runs[runID]);

		// XXX: remove dirty
	}

	/**
	 * Huge alloc/free facilities.
	 */
	void* allocHuge(size_t size) {
		// TODO: in contracts
		assert(size > SizeClass.Large);

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
		auto ret = map_chunks(((size - 1) >> LgChunkSize) + 1);
		if (ret is null) {
			free(e);
			return null;
		}

		e.addr = ret;
		e.size = size;

		hugeTree.insert(e);

		return ret;
	}

	Extent* extractHugeExtent(void* ptr) {
		// XXX: in contracts
		import d.gc.spec;
		assert(((cast(size_t) ptr) & ChunkAlignMask) == 0);

		Extent test;
		test.addr = ptr;
		auto e = hugeTree.extract(&test);
		if (e is null) {
			e = hugeLookupTree.extract(&test);
		}

		// FIXME: out contract.
		if (e !is null) {
			assert(e.addr is ptr);
			assert(e.arena is &this);
		}

		return e;
	}

	void freeHuge(void* ptr) {
		if (ptr is null) {
			// free(null) is valid, we want to handle it properly.
			return;
		}

		freeExtent(extractHugeExtent(ptr));
	}

	void freeExtent(Extent* e) {
		// FIXME: in contract
		assert(e !is null);
		assert(hugeTree.find(e) is null);
		assert(hugeLookupTree.find(e) is null);

		import d.gc.mman;
		pages_unmap(e.addr, e.size);

		free(e);
	}

	/**
	 * GC facilities
	 */
	void addRoots(const void[] range) {
		// FIXME: Casting to void* is aparently not handled properly :(
		auto ptr = cast(void*) roots.ptr;

		// We realloc everytime. It doesn't really matter at this point.
		roots.ptr = cast(const(void*)[]*)
			realloc(ptr, (roots.length + 1) * void*[].sizeof);

		// Using .ptr to bypass bound checking.
		roots.ptr[roots.length] = makeRange(range);

		// Update the range.
		roots = roots.ptr[0 .. roots.length + 1];
	}

	void collect() {
		// Get ready to detect huge allocations.
		hugeLookupTree = hugeTree;

		// FIXME: This bypass visibility.
		hugeTree.root = null;

		// TODO: The set need a range interface or some other way to iterrate.
		auto chunks = chunkSet.cloneChunks();
		foreach (c; chunks) {
			if (c is null) {
				continue;
			}

			c.prepare();
		}

		// Mark bitmap as live.
		foreach (c; chunks) {
			if (c is null) {
				continue;
			}

			auto bmp = cast(void**) &c.header.bitmap;
			scan(bmp[0 .. 1]);
		}

		// Scan the roots !
		__sdgc_push_registers(scanStack);
		foreach (range; roots) {
			scan(range);
		}

		// Go on and on until all worklists are empty.
		auto needRescan = true;
		while (needRescan) {
			needRescan = false;
			foreach (c; chunks) {
				if (c is null) {
					continue;
				}

				needRescan = c.scan() || needRescan;
			}
		}

		// Now we can collect.
		foreach (c; chunks) {
			if (c is null) {
				continue;
			}

			c.collect();
		}

		// Extents that have not been moved to hugeTree are dead.
		while (!hugeLookupTree.empty) {
			freeExtent(hugeLookupTree.extractAny());
		}
	}

	bool scanStack() {
		const(void*) p;

		auto iptr = cast(size_t) &p;
		auto iend = cast(size_t) stackBottom;
		auto length = (iend - iptr) / size_t.sizeof;

		auto range = (&p)[1 .. length];
		return scan(range);
	}

	bool scan(const(void*)[] range) {
		bool newPtr;
		foreach (ptr; range) {
			auto iptr = cast(size_t) ptr;

			import d.gc.spec;
			auto c = findChunk(ptr);
			if (c !is null && chunkSet.test(c)) {
				newPtr = c.mark(ptr) || newPtr;
				continue;
			}

			Extent ecmp;
			ecmp.addr = cast(void*) ptr;
			auto e = hugeLookupTree.extract(&ecmp);
			if (e is null) {
				continue;
			}

			hugeTree.insert(e);

			auto hugeRange = makeRange(e.addr[0 .. e.size]);

			// FIXME: Ideally, a worklist is preferable as
			// 1/ We could recurse a lot this way.
			// 2/ We want to keep working on the same chunk for locality.
			scan(hugeRange);
		}

		return newPtr;
	}
}

private:

/**
 * This function get a void[] range and chnage it into a
 * const(void*)[] one, reducing to alignement boundaries.
 */
const(void*)[] makeRange(const void[] range) {
	size_t iptr = cast(size_t) range.ptr;
	auto aiptr = (((iptr - 1) / size_t.sizeof) + 1) * size_t.sizeof;

	// Align the ptr and remove the differnece from the length.
	auto aptr = cast(const(void*)*) aiptr;
	if (range.length < 8) {
		return aptr[0 .. 0];
	}

	auto length = (range.length - aiptr + iptr) / size_t.sizeof;
	return aptr[0 .. length];
}

struct ChunkSet {
	// Set of chunks for GC lookup.
	Chunk** chunks;
	uint chunkCount;

	// Metadatas for the chunk set.
	ubyte lgChunkSetSize;
	ubyte maxProbe;

	@property
	Arena* arena() {
		// We can find the arena from this pointer.
		auto chunkSetOffset = cast(size_t) (&(cast(Arena*) null).chunkSet);
		return cast(Arena*) ((cast(size_t) &this) - chunkSetOffset);
	}

	import d.gc.chunk;
	bool register(Chunk* c) {
		// FIXME: in contract
		assert(!test(c));

		// We resize if the set is 7/8 full.
		auto limitSize = (7UL << lgChunkSetSize) / 8;
		if (limitSize <= chunkCount) {
			if (increaseSize()) {
				return true;
			}
		}

		chunkCount++;
		insert(c);

		// FIXME: out contract
		assert(test(c));
		return false;
	}

	/**
	 * GC facilities
	 */
	bool test(Chunk* c) {
		// FIXME: in contract
		assert(c !is null);

		import d.gc.spec;
		auto k = (cast(size_t) c) >> LgChunkSize;
		auto mask = (1 << lgChunkSetSize) - 1;

		foreach (i; 0 .. maxProbe) {
			if (c is chunks[(k + i) & mask]) {
				return true;
			}
		}

		return false;
	}

	Chunk*[] cloneChunks() {
		auto oldLgChunkSetSize = lgChunkSetSize;
		auto allocSize = size_t.sizeof << lgChunkSetSize;
		auto buf = cast(Chunk**) arena.alloc(allocSize);

		// We may have created a new chunk to allocate the buffer.
		while (lgChunkSetSize != oldLgChunkSetSize) {
			// If don't think this can run more than once,
			// but better safe than sorry.
			oldLgChunkSetSize = lgChunkSetSize;
			allocSize = size_t.sizeof << lgChunkSetSize;
			buf = cast(Chunk**) arena.realloc(buf, allocSize);
		}

		memcpy(buf, chunks, allocSize);
		return buf[0 .. 1UL << lgChunkSetSize];
	}

private:
	/**
	 * Internal facilities
	 */
	void insert(Chunk* c) {
		auto mask = (1 << lgChunkSetSize) - 1;

		import d.gc.spec;
		auto k = (cast(size_t) c) >> LgChunkSize;
		auto p = (cast(uint) k) & mask;

		auto i = p;
		ubyte d = 0;
		while (chunks[i] !is null) {
			auto ce = chunks[i];
			auto ke = (cast(size_t) ce) >> LgChunkSize;
			auto pe = (cast(uint) ke) & mask;

			// Robin hood hashing.
			if (d > (i - pe)) {
				chunks[i] = c;
				c = ce;
				k = ke;
				p = pe;

				if (d >= maxProbe) {
					maxProbe = cast(ubyte) (d + 1);
				}
			}

			i = ((i + 1) & mask);
			d = cast(ubyte) (i - p);
		}

		chunks[i] = c;
		if (d >= maxProbe) {
			maxProbe = cast(ubyte) (d + 1);
		}
	}

	bool increaseSize() {
		auto oldChunks = chunks;
		auto oldChunkSetSize = 1UL << lgChunkSetSize;

		lgChunkSetSize++;
		assert(lgChunkSetSize <= 32);

		import d.gc.spec;
		// auto newChunks = cast(Chunk**) arena.calloc(Chunk*.sizeof << lgChunkSetSize);
		auto newChunks =
			cast(Chunk**) arena.calloc(size_t.sizeof << lgChunkSetSize);
		assert(oldChunks is chunks);

		if (newChunks is null) {
			return true;
		}

		maxProbe = 0;
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

extern(C):
version(OSX) {
	// For some reason OSX's symbol get a _ prepended.
	bool _sdgc_push_registers(bool delegate());
	alias __sdgc_push_registers = _sdgc_push_registers;
} else {
	bool __sdgc_push_registers(bool delegate());
}
