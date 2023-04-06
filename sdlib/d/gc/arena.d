module d.gc.arena;

import d.gc.spec;

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
	// FIXME: All of this is shared, but ultimately,
	// the arena is what needs to be shared.
	import d.gc.base;
	shared Base base;

	import d.gc.allocator;
	shared Allocator _allocator;

	@property
	shared(Allocator)* allocator() {
		auto a = &_allocator;

		if (a.regionAllocator is null) {
			import d.gc.region;
			a.regionAllocator = gRegionAllocator;

			import d.gc.emap;
			a.emap = gExtentMap;
		}

		return a;
	}

	/**
	 * Legacy Arena.
	 *
	 * The arena is being migrated from being thread unsafe
	 * and use the Chunk based allocator to being thread safe
	 * and use the huge page allocator.
	 *
	 * In order to keep everythign working as we go, the legacy
	 * mechanism are left as this and the code migrated path by path.
	 * Once everything is migrated, everythign in that section
	 * will be removed.
	 */
	import d.sync.mutex;
	shared Mutex chunkMutex;

	// Spare chunk to avoid churning too much.
	import d.gc.chunk;
	Chunk* spare;

	// Free runs we can allocate from.
	import d.gc.rbtree, d.gc.run;
	RBTree!(RunDesc, sizeAddrRunCmp) freeRunTree;

	// Set of chunks for GC lookup.
	ChunkSet chunkSet;

	// Extent describing huge allocs.
	shared Mutex hugeMutex;

	import d.gc.extent;
	ExtentTree hugeTree;
	ExtentTree hugeLookupTree;

	const(void*)* stackBottom;
	const(void*)[][] roots;

	import d.gc.bin, d.gc.sizeclass;
	Bin[ClassCount.Small] bins;

	void* alloc(size_t size) {
		if (size <= SizeClass.Small) {
			return allocSmall(size);
		}

		return allocLarge(size, false);
	}

	void* calloc(size_t size) {
		if (size <= SizeClass.Small) {
			auto ret = allocSmall(size);
			memset(ret, 0, size);
			return ret;
		}

		return allocLarge(size, true);
	}

	void free(void* ptr) {
		if (ptr is null) {
			return;
		}

		import d.gc.util;
		auto aptr = alignDown(ptr, PageSize);

		auto a = allocator;
		auto pd = a.emap.lookup(aptr);
		assert(pd.extent !is null);
		assert(pd.isSlab() || ptr is pd.extent.addr);

		if (!pd.isSlab() || bins[pd.sizeClass].free(&this, ptr, pd)) {
			a.freePages(pd.extent);
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

		import d.gc.util;
		auto aptr = alignDown(ptr, PageSize);

		auto a = allocator;
		auto pd = a.emap.lookup(aptr);
		assert(pd.extent !is null);
		assert(pd.isSlab() || ptr is pd.extent.addr);

		auto copySize = size;
		if (pd.isSlab()) {
			auto newSizeClass = getSizeClass(size);
			auto oldSizeClass = pd.sizeClass;
			if (newSizeClass == oldSizeClass) {
				return ptr;
			}

			if (newSizeClass > oldSizeClass) {
				copySize = getSizeFromClass(oldSizeClass);
			}
		} else {
			auto esize = pd.extent.size;
			if (alignUp(size, PageSize) == esize) {
				return ptr;
			}

			// TODO: Try to extend/shrink in place.
			import d.gc.util;
			copySize = min(size, esize);
		}

		auto newPtr = alloc(size);
		if (newPtr is null) {
			return null;
		}

		memcpy(newPtr, ptr, copySize);

		if (!pd.isSlab() || bins[pd.sizeClass].free(&this, ptr, pd)) {
			a.freePages(pd.extent);
		}

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

		auto sizeClass = getSizeClass(size);
		assert(sizeClass < ClassCount.Small);

		return bins[sizeClass].alloc(&this, sizeClass);
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(size_t size, bool zero) {
		// FIXME: in contracts.
		assert(size > SizeClass.Small);

		import d.gc.util;
		uint pages = (alignUp(size, PageSize) >> LgPageSize) & uint.max;
		auto e = allocator.allocPages(&this, pages);
		return e.addr;
	}

	/**
	 * Free in chunk.
	 */
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

		auto runBinID =
			cast(ubyte) (getSizeClass((pages << LgPageSize) + 1) - 1);

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
	void freeExtent(Extent* e) {
		// FIXME: in contract
		assert(e !is null);
		assert(hugeMutex.isHeld(), "Mutex not held!");
		assert(hugeTree.find(e) is null);
		assert(hugeLookupTree.find(e) is null);

		hugeMutex.unlock();
		scope(exit) hugeMutex.lock();

		import d.gc.pages;
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
		{
			hugeMutex.lock();
			scope(exit) hugeMutex.unlock();

			// Get ready to detect huge allocations.
			hugeLookupTree = hugeTree;

			// FIXME: This bypass visibility.
			hugeTree.root = null;
		}

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

		hugeMutex.lock();
		scope(exit) hugeMutex.unlock();

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
		if (chunks is null) {
			return [];
		}

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
