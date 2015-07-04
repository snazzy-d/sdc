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
		assert(this.large == large);
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
		return !(bits & 0x02);
	}
	
	@property
	bool large() const {
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
		assert(!allocated);
		// TODO: VRP
		return bits >> LgPageSize;
	}
	
	@property
	uint size() const {
		assert(!allocated);
		// TODO: VRP
		return cast(uint) (bits & ~PageMask);
	}
}

enum DataPages	= computeDataPages();

struct Chunk {
	// 23 first pages are for header.
	import d.gc.extent;
	Extent header;
	
	uint[1024 - DataPages - (Extent.sizeof / 4)] pad0;
	
	// 1 page including header.
	PageDescriptor[DataPages] pages;
	
	// 22 pages.
	import d.gc.run;
	RunDesc[DataPages] runs;
	
	uint[((1023 - DataPages) * PageSize - DataPages * RunDesc.sizeof) / 4] pad1;
	
	// 1001 pages left for data.
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
		
		// XXX: ensure i didn't fucked up the layout.
		// this better belong to static assert when available.
		auto ci = cast(size_t) ret;
		auto ri = cast(size_t) &c.runs[0];
		auto pi = cast(size_t) &c.datas[0];
		
		assert(ri == ci + PageSize);
		assert(pi - ci == (1024 - DataPages) * PageSize);
		
		c.header.arena	= a;
		c.header.addr	= c;
		c.header.size	= ChunkSize;
		
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
	
	uint splitSmallRun(uint runID, ubyte binID) {
		// XXX: in contract.
		import d.gc.bin, d.gc.sizeclass;
		assert(binID < ClassCount.Small);
		assert(!pages[runID].allocated);
		
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
		
		runs[runID].misc.small.binID = binID;
		runs[runID].misc.small.freeSlots = binInfo.freeSlots;
		
		auto bits = binInfo.freeSlots / 32;
		runs[runID].misc.small.header = cast(ushort) ((1 << bits) - 1);
		for (uint i = 0; i < bits; i++) {
			runs[runID].misc.small.bitmap[i] = -1;
		}
		
		return rem;
	}
	
	uint splitLargeRun(size_t size, uint runID, ubyte binID, bool zero) {
		// XXX: in contract.
		import d.gc.bin, d.gc.sizeclass;
		assert(size >= SizeClass.Small && size < SizeClass.Large);
		assert(binID >= ClassCount.Small && binID < ClassCount.Large);
		assert(!pages[runID].allocated);
		assert(size == getAllocSize(size));
		assert(getBinID(size) == binID);
		
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

private:

auto computeDataPages() {
	uint pages = 1023;
	while(pages--) {
		import d.gc.run;
		auto miscPages = (((pages * RunDesc.sizeof) - 1) >> LgPageSize) + 1;
		
		auto availPages = 1023 - pages;
		if (miscPages <= availPages) {
			return pages;
		}
	}
	
	return 0;
}

