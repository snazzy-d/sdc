module d.gc.chunk;

import d.gc.spec;

struct PageDescriptor {
	/**
	 * This is similar but not identical to what jemalloc does.
	 * Visit: http://www.canonware.com/jemalloc/ to know more.
	 *
	 * Run address (or size) and various flags are stored together.  The bit
	 * layout looks like:
	 *
	 *   ???????? ???????? ????nnnn nnnndula
	 *
	 * ? : Unallocated: Run address for first/last pages, unset for internal
	 *                  pages.
	 *     Small: Run page offset.
	 *     Large: Run size for first page, unset for trailing pages.
	 * n : binind for small size class, BININD_INVALID for large size class.
	 * d : dirty?
	 * u : unzeroed?
	 * l : large?
	 * a : allocated?
	 *
	 * Following are example bit patterns for the three types of runs.
	 *
	 * p : run page offset
	 * s : run size
	 * n : binind for size class; large objects set these to BININD_INVALID
	 * x : don't care
	 * - : 0
	 * + : 1
	 * [DULA] : bit set
	 * [dula] : bit unset
	 *
	 *   Unallocated (clean):
	 *     ssssssss ssssssss ssss++++ ++++du-a
	 *     xxxxxxxx xxxxxxxx xxxxxxxx xxxx-Uxx
	 *     ssssssss ssssssss ssss++++ ++++dU-a
	 *
	 *   Unallocated (dirty):
	 *     ssssssss ssssssss ssss++++ ++++D--a
	 *     xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
	 *     ssssssss ssssssss ssss++++ ++++D--a
	 *
	 *   Small:
	 *     pppppppp pppppppp ppppnnnn nnnnd--A
	 *     pppppppp pppppppp ppppnnnn nnnn---A
	 *     pppppppp pppppppp ppppnnnn nnnnd--A
	 *
	 *   Large:
	 *     pppppppp pppppppp ppppnnnn nnnnD-LA
	 *     pppppppp pppppppp ppppnnnn nnnnD-LA
	 *     pppppppp pppppppp ppppnnnn nnnnD-LA
	 */
	private uint bits;
	
	this(bool allocated, bool large, bool zeroed, bool dirty, ubyte binID, uint pages) {
		// XXX: in contract.
		assert(allocated || !large);
		
		bits = allocated;
		
		bits |= (cast(uint) large) << 1;
		bits |= (cast(uint) !zeroed) << 2;
		bits |= (cast(uint) dirty) << 3;
		bits |= (cast(uint) binID) << 4;
		bits |= (pages << LgPageSize);
		
		// Sanity checks.
		assert(this.allocated == allocated);
		assert(this.free || this.large == large);
		assert(this.zeroed == zeroed);
		assert(this.dirty == dirty);
		assert(this.binID == binID);
	}
	
	@property
	bool allocated() const {
		return !free;
	}
	
	@property
	bool free() const {
		// TODO: VRP for &
		return !(bits & 0x01);
	}
	
	@property
	bool small() const {
		assert(allocated);
		return !(bits & 0x02);
	}
	
	@property
	bool large() const {
		assert(allocated);
		return !small;
	}
	
	@property
	bool zeroed() const {
		return !(bits & 0x04);
	}
	
	@property
	bool dirty() const {
		return !!(bits & 0x08);
	}
	
	@property
	ubyte binID() const {
		return cast(ubyte) (bits >> 4);
	}
	
	@property
	uint offset() const {
		assert(allocated);
		return bits >> LgPageSize;
	}
	
	@property
	uint pages() const {
		assert(free);
		// TODO: VRP
		return bits >> LgPageSize;
	}
	
	@property
	uint size() const {
		assert(free);
		// TODO: VRP
		return cast(uint) (bits & ~PageMask);
	}
}

struct Chunk {
	// header + pad0 + DataPages populate the first page.
	Header header;
	alias header this;
	
	// Pad header so that the first page descriptor is at the right place.
	PageDescriptor[Pad0Size] pad0;
	
	// One PageDescriptor per data page pages.
	PageDescriptor[DataPages] pages;
	
	// One RunDesc per data page.
	import d.gc.run;
	RunDesc[DataPages] runs;
	
	// Pad metadata up to the end of the current page.
	uint[Pad1Size] pad1;
	
	// Actual user data.
	ulong[PageSize / ulong.sizeof][DataPages] datas;
	
	import d.gc.arena;
	static Chunk* allocate(Arena* a) {
		// XXX: ensure i didn't fucked up the layout.
		// this better belong to static assert when available.
		assert(Chunk.sizeof == ChunkSize);
		
		import d.gc.mman;
		auto ret = map_chunks(1);
		if (ret is null) {
			return null;
		}
		
		auto c = cast(Chunk*) ret;
		assert(findChunk(c) is null);
		
		// XXX: ensure I didn't fucked up the layout.
		// this better belong to static assert when available.
		{
			auto ci = cast(size_t) ret;
			auto pi = cast(size_t) &c.pages[0];
			auto ri = cast(size_t) &c.runs[0];
			auto di = cast(size_t) &c.datas[0];
			
			assert(pi == ci + MetaPages * PageDescriptor.sizeof);
			assert(ri == ci + ChunkPageCount * PageDescriptor.sizeof);
			assert(di == ci + MetaPages * PageSize);
		}

		c.arena	 = a;
		c.addr   = c;
		c.size   = ChunkSize;
		c.bitmap = null;
		
		// FIXME: empty array not supported.
		// c.worklist = [];
		c.worklist.ptr = null;
		c.worklist.length = 0;
		
		import d.gc.sizeclass;
		enum DataSize = DataPages << LgPageSize;
		enum FreeBinID = cast(ubyte) (getBinID(DataSize + 1) - 1);
		
		import d.gc.bin;
		auto d = PageDescriptor(
			false,
			false,
			true,
			false,
			FreeBinID,
			DataPages,
		);
		
		assert(d.zeroed == true);
		assert(!d.allocated);
		assert(d.size == DataSize);
		assert(d.binID == FreeBinID);
		
		c.pages[0] = d;
		c.pages[DataPages - 1] = d;
		
		// TODO: register the chunk for dump and scan.
		return c;
	}
	
	void free() {
		import d.gc.mman;
		pages_unmap(&this, ChunkSize);
	}
	
	uint getPageID(const void* ptr) {
		// FIXME: in contract
		assert(findChunk(ptr) is &this);
		
		auto offset = (cast(uint) ptr) - (cast(uint) &datas[0]);
		
		import d.gc.spec;
		return offset >> LgPageSize;
	}
	
	uint getRunID(const void* ptr) {
		// FIXME: in contract
		assert(findChunk(ptr) is &this);
		
		auto pageID = getPageID(ptr);
		auto pd = pages[pageID];
		assert(pd.allocated);
		
		auto runID = pageID - pd.offset;
		
		// FIXME: out contract
		assert(pages[runID].allocated);
		return runID;
	}
	
	uint maybeGetRunID(const void* ptr) {
		// FIXME: in contract
		assert(findChunk(ptr) is &this);
		
		auto pageID = getPageID(ptr);
		if (pageID >= DataPages) {
			return -1;
		}
		
		auto pd = pages[pageID];
		if (pd.free) {
			return -1;
		}
		
		// Find the start of the run.
		auto runID = pageID - pd.offset;
		pd = pages[runID];
		if (pd.free) {
			return -1;
		}
		
		return runID;
	}
	
	/**
	 * GC facilities.
	 */
	void prepare() {
		ushort nextBitmapIndex = ((DataPages - 1) / (uint.sizeof * 8)) + 1;
		uint i = 0;
		while (i < DataPages) {
			if (pages[i].free) {
				auto runID = i;
				i += pages[i].pages;
				
				assert(pages[i - 1].free);
				assert(pages[i - 1].pages == pages[runID].pages);
				
				continue;
			}
			
			auto binID = pages[i].binID;
			if (pages[i].large) {
				import d.gc.sizeclass;
				i += cast(uint) (getSizeFromBinID(binID) >> LgPageSize);
				continue;
			}
			
			// For small runs, we make sure we reserve some place in the chunk's bitmap.
			assert(pages[i].offset == 0);
			assert(runs[i].small.bitmapIndex == 0);
			runs[i].small.bitmapIndex = nextBitmapIndex;
			
			import d.gc.bin;
			i += binInfos[binID].needPages;
			
			auto slots = binInfos[binID].slots;
			nextBitmapIndex += cast(ushort) (((slots - 1) / (uint.sizeof * 8)) + 1);
		}
		
		// FIXME: It seems that there are some issue with alias this.
		header.bitmap = cast(uint*) header.arena.calloc(nextBitmapIndex * uint.sizeof);
	}
	
	bool mark(const void* ptr) {
		assert(findChunk(ptr) is &this);
		
		auto runID = maybeGetRunID(ptr);
		if (runID == -1) {
			return false;
		}
		
		// The chunk may have been created after the collection started.
		auto bitmapPtr = header.bitmap;
		if (bitmapPtr is null) {
			return false;
		}
		
		auto pd = pages[runID];
		auto index = runID;
		if (pd.small) {
			auto smallRun = &runs[runID].small;
			
			// This run has been alocated after the start of the collection.
			// We just consider it alive, no need to check for it.
			auto bitmapIndex = smallRun.bitmapIndex;
			if (bitmapIndex == 0) {
				return false;
			}
			
			bitmapPtr = &bitmapPtr[bitmapIndex];
			
			// This is duplicated with Arena.freeSmall, need refactoring.
			auto offset = (cast(uint) ptr) - (cast(uint) &datas[runID]);
			
			import d.gc.bin;
			index = offset / binInfos[pd.binID].size;
			if (smallRun.isFree(index)) {
				return false;
			}
		}
		
		// Already marked
		auto elementBitmap = bitmapPtr[index / 32];
		auto mask = 1 << (index % 32);
		if (elementBitmap & mask) {
			return false;
		}
		
		// Mark and add to worklist
		bitmapPtr[index / 32] = elementBitmap | mask;
		
		auto workLength = header.worklist.length + 1;
		
		// We realloc everytime. It doesn't really matter at this point.
		auto workPtr = cast(const(void)**) header.arena.realloc(header.worklist.ptr, workLength * void*.sizeof);
		
		workPtr[workLength - 1] = ptr;
		header.worklist = workPtr[0 .. workLength];
		
		return true;
	}
	
	bool scan() {
		auto newPtr = false;
		
		while (header.worklist.length > 0) {
			auto ptrs = header.worklist;
			scope(exit) header.arena.free(ptrs.ptr);
			
			// header.worklist = [];
			header.worklist.ptr = null;
			header.worklist.length = 0;
			
			foreach(ptr; ptrs) {
				assert(findChunk(ptr) is &this);
				
				auto runID = maybeGetRunID(ptr);
				if (runID == -1) {
					continue;
				}
				
				auto pd = pages[runID];
				assert(pd.allocated);
				assert(pd.offset == 0);
				
				auto base = cast(const(void*)*) &datas[runID];
				
				const(void*)[] range;
				size_t size;
				
				if (pd.small) {
					import d.gc.bin;
					size = binInfos[pd.binID].size;
					auto offset = (cast(uint) ptr) - (cast(uint) base);
					auto index = offset / size;
					base = cast(const(void*)*) ((cast(void*) base) + size * index);
				} else {
					import d.gc.sizeclass;
					size = getSizeFromBinID(pd.binID);
				}
				
				range = base[0 .. size / size_t.sizeof];
				newPtr = header.arena.scan(range) || newPtr;
			}
		}
		
		return newPtr;
	}
	
	void collect() {
		uint i = 0;
		while (i < DataPages) {
			if (pages[i].free) {
				auto runID = i;
				i += pages[i].pages;
				
				assert(pages[i - 1].free);
				assert(pages[i - 1].pages == pages[runID].pages);
				
				continue;
			}
			
			auto pd = pages[i];
			auto runID = i;
			auto binID = pd.binID;
			if (pd.large) {
				import d.gc.sizeclass;
				auto pages = cast(uint) (getSizeFromBinID(pd.binID) >> LgPageSize);
				i += pages;
				
				// Check if the run is alive.
				auto bmp = header.bitmap[runID / 32];
				auto mask = 1 << (runID % 32);
				if (bmp & mask) {
					continue;
				}
				
				header.arena.freeRun(&this, runID, pages);
				continue;
			}
			
			assert(pd.offset == 0);
			
			import d.gc.bin;
			auto binInfo = binInfos[binID];
			i += binInfo.needPages;
			
			auto small = &runs[runID].small;
			auto bmpIndex = small.bitmapIndex;
			// This is a new run, dismiss.
			if (bmpIndex == 0) {
				continue;
			}
			
			auto bitmapPtr = &header.bitmap[bmpIndex];
			auto headerBits = binInfo.slots / 32;
			if (!headerBits) {
				headerBits = 1;
			} else {
				assert((binInfo.slots % 32) == 0);
			}
			
			for (uint j = 0; j < headerBits; j++) {
				auto liveBmp = bitmapPtr[j];
				
				// Zero means allocated, so we flip bits.
				auto oldBmp = small.bitmap[j];
				auto newBmp = oldBmp | ~liveBmp;
				
				auto freed = newBmp ^ oldBmp;
				if (freed) {
					import d.gc.util;
					small.freeSlots += popcount(freed);
					small.header = cast(ushort)  (small.header | (1 << i));
					small.bitmap[j] = newBmp;
				}
			}
		}
		
		// FIXME: It seems that there are some issue with alias this.
		header.arena.free(header.bitmap);
		header.bitmap = null;
		
		// FIXME: empty array not supported.
		// header.worklist = [];
		assert(header.worklist.ptr is null);
		assert(header.worklist.length == 0);
	}
	
	/**
	 * Split run from free space.
	 */
	uint splitSmallRun(uint runID, ubyte binID) {
		// XXX: in contract.
		import d.gc.bin, d.gc.sizeclass;
		assert(binID < ClassCount.Small);
		assert(pages[runID].free);
		
		auto binInfo = binInfos[binID];
		auto needPages = binInfo.needPages;
		
		assert((needPages << LgPageSize) <= pages[runID].size);
		auto rem = runSplitRemove(runID, needPages);
		
		auto dirty = pages[runID].dirty;
		
		setBitmap(runID, needPages, PageDescriptor(
			true,
			false,
			false,
			dirty,
			binID,
			0,
		));
		
		runs[runID].small.binID = binID;
		runs[runID].small.freeSlots = binInfo.slots;
		
		// During the collection process, other runs may be created,
		// they are considered live and will be scanned during the next
		// collection cycle.
		runs[runID].small.bitmapIndex = 0;
		
		auto headerBits = binInfo.slots / 32;
		if (!headerBits) {
			runs[runID].small.header = 1;
			runs[runID].small.bitmap[0] = (1 << (binInfo.slots % 32)) - 1;
			return rem;
		}
		
		assert((binInfo.slots % 32) == 0);
		
		runs[runID].small.header = cast(ushort) ((1 << headerBits) - 1);
		for (uint i = 0; i < headerBits; i++) {
			runs[runID].small.bitmap[i] = -1;
		}
		
		return rem;
	}
	
	uint splitLargeRun(size_t size, uint runID, ubyte binID, bool zero) {
		// XXX: in contract.
		import d.gc.bin, d.gc.sizeclass;
		assert(size > SizeClass.Small && size <= SizeClass.Large);
		assert(binID >= ClassCount.Small && binID < ClassCount.Large);
		assert(pages[runID].free);
		assert(size == getAllocSize(size));
		assert(getBinID(size) == binID);
		
		// If we are GCing, mark the new allocation as live.
		auto bPtr = header.bitmap;
		if (bPtr !is null) {
			bPtr = &bPtr[runID / 32];
			*bPtr = *bPtr | (1 << (runID % 32));
		}
		
		auto needPages = cast(uint) (size >> LgPageSize);
		auto rem = runSplitRemove(runID, needPages);
		
		auto dirty = pages[runID].dirty;
		if (zero) {
			if (dirty) {
				memset(&datas[runID], 0, needPages << LgPageSize);
			} else {
				for (uint i = 0; i < needPages; i++) {
					auto p = runID + i;
					if (!pages[p].zeroed) {
						memset(&datas[p], 0, PageSize);
					}
				}
			}
		}
		
		setBitmap(runID, needPages, PageDescriptor(
			true,
			true,
			zero,
			dirty,
			binID,
			0,
		));
		
		return rem;
	}
	
private:
	void setBitmap(uint runID, uint needPages, PageDescriptor base) {
		// FIXME: in contract
		assert(base.allocated);
		
		for (uint i = 0; i < needPages; i++) {
			auto p = runID + i;
			auto d = pages[p];
			
			pages[p] = PageDescriptor(
				base.allocated,
				base.large,
				base.zeroed,
				base.dirty,
				base.binID,
				i,
			);
			
			if (d.zeroed && !base.dirty) {
				for (uint j; j < datas[p].length; j++) {
					assert(datas[p][j] == 0);
				}
			}
		}
	}
	
	uint runSplitRemove(uint runID, uint needPages) {
		// XXX: in contract.
		assert(!pages[runID].allocated);
		
		auto pd = pages[runID];
		auto totalPages = pd.pages;
		auto dirty = pd.dirty;
		
		assert(needPages <= totalPages);
		auto remPages = totalPages - needPages;
		
		if (dirty) {
			// XXX: arena dirty remove.
		}
		
		if (remPages == 0) {
			return 0;
		}
		
		import d.gc.sizeclass;
		auto remBin = cast(ubyte) (getBinID((remPages << LgPageSize) + 1) - 1);
		
		// If we have remaining free space, keep track of it.
		import d.gc.bin;
		auto d = PageDescriptor(
			false,
			false,
			pd.zeroed,
			dirty,
			remBin,
			remPages,
		);
		
		pages[runID + needPages] = d;
		pages[runID + totalPages - 1] = d;
		
		if (dirty) {
			// XXX: arena dirty add.
		}
		
		return runID + needPages;
	}
}

Chunk* findChunk(const void* ptr) {
	import d.gc.spec;
	auto c = cast(Chunk*) ((cast(size_t) ptr) & ~AlignMask);
	
	// XXX: type promotion is fucked.
	auto vc = cast(void*) c;
	if (vc is ptr) {
		// Huge alloc, no arena.
		return null;
	}
	
	return c;
}

private:

struct Header {
	import d.gc.extent;
	Extent extent;
	alias extent this;
	
	uint* bitmap;
	const(void)*[] worklist;
}

enum DataPages = computeDataPages();
enum MetaPages = ChunkPageCount - DataPages;

enum MinMetaPages = ((Header.sizeof - 1) / /+ PageDescriptor.alignof +/ 4) + 1;
enum Pad0Size = MetaPages - MinMetaPages;
enum Pad1Size = ((MetaPages * PageSize) - computeRunDescEnd(DataPages)) / uint.sizeof;

auto computeDataPages() {
	foreach (metaPages; MinMetaPages .. ChunkPageCount) {
		auto dataPages = ChunkPageCount - metaPages;
		auto runDescEnd = computeRunDescEnd(dataPages);
		auto requiredMetaPages = ((runDescEnd - 1) >> LgPageSize) + 1;

		if (requiredMetaPages == metaPages) {
			return dataPages;
		}
	}

	assert(0, "Chunk is too small");
}

auto computeRunDescEnd(size_t dataPages) {
	auto pageDescEnd = ChunkPageCount * PageDescriptor.sizeof;
	
	import d.gc.run;
	enum RDAlign = /+ RunDesc.alignof +/ 8;
	auto runDescStart = (((pageDescEnd - 1) / RDAlign) + 1) * RDAlign;

	return runDescStart + dataPages * RunDesc.sizeof;
}
