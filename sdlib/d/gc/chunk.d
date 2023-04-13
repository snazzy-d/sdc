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

	this(bool allocated, bool large, bool zeroed, bool dirty, ubyte binID,
	     uint pages) {
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

		import d.gc.pages;
		auto ret = pages_map(null, ChunkSize, ChunkSize);
		if (ret is null) {
			return null;
		}

		auto c = cast(Chunk*) ret;
		assert(findChunk(c) is null);

		// FIXME: Ensure the layout is as expected.
		// This is better achieved as static assert.
		{
			auto ci = cast(size_t) ret;
			auto pi = cast(size_t) &c.pages[0];
			auto ri = cast(size_t) &c.runs[0];
			auto di = cast(size_t) &c.datas[0];

			assert(pi == ci + MetaPages * PageDescriptor.sizeof);
			assert(ri == ci + ChunkPageCount * PageDescriptor.sizeof);
			assert(di == ci + MetaPages * PageSize);
		}

		c.arena = a;
		c.header.extent.at(c, ChunkSize, null);
		c.bitmap = null;

		// FIXME: empty array not supported.
		// c.worklist = [];
		c.worklist.ptr = null;
		c.worklist.length = 0;

		import d.gc.sizeclass;
		enum DataSize = DataPages << LgPageSize;
		enum FreeBinID = cast(ubyte) (getSizeClass(DataSize + 1) - 1);

		import d.gc.bin;
		auto d =
			PageDescriptor(false, false, true, false, FreeBinID, DataPages);

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
		import d.gc.pages;
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
			assert(pages[i].large);

			import d.gc.sizeclass;
			i += cast(uint) (getSizeFromClass(binID) >> LgPageSize);
		}

		// FIXME: It seems that there are some issue with alias this.
		header.bitmap =
			cast(uint*) header.arena.calloc(nextBitmapIndex * uint.sizeof);
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
		assert(!pd.small);

		// Already marked
		auto elementBitmap = bitmapPtr[index / 32];
		auto mask = 1 << (index % 32);
		if (elementBitmap & mask) {
			return false;
		}

		// Mark and add to worklist.
		bitmapPtr[index / 32] = elementBitmap | mask;

		auto workLength = header.worklist.length + 1;

		// We realloc everytime. It doesn't really matter at this point.
		auto workPtr = cast(const(void)**)
			header.arena
			      .realloc(header.worklist.ptr, workLength * void*.sizeof);

		workPtr[workLength - 1] = ptr;
		header.worklist = workPtr[0 .. workLength];

		return true;
	}

	bool scan() {
		bool newPtr = false;

		while (header.worklist.length > 0) {
			auto ptrs = header.worklist;
			scope(exit) header.arena.free(ptrs.ptr);

			// header.worklist = [];
			header.worklist.ptr = null;
			header.worklist.length = 0;

			foreach (ptr; ptrs) {
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

				assert(!pd.small);

				import d.gc.sizeclass;
				size = getSizeFromClass(pd.binID);

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

			assert(pd.large);
			import d.gc.sizeclass;
			auto pages = cast(uint) (getSizeFromClass(pd.binID) >> LgPageSize);
			i += pages;

			// Check if the run is alive.
			auto bmp = header.bitmap[runID / 32];
			auto mask = 1 << (runID % 32);
			if (bmp & mask) {
				continue;
			}

			// header.arena.freeRun(&this, runID, pages);
		}

		// FIXME: It seems that there are some issue with alias this.
		header.arena.free(header.bitmap);
		header.bitmap = null;

		// FIXME: empty array not supported.
		// header.worklist = [];
		assert(header.worklist.ptr is null);
		assert(header.worklist.length == 0);
	}
}

Chunk* findChunk(const void* ptr) {
	import d.gc.spec;
	auto c = cast(Chunk*) ((cast(size_t) ptr) & ~ChunkAlignMask);

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
enum Pad1Size =
	((MetaPages * PageSize) - computeRunDescEnd(DataPages)) / uint.sizeof;

auto computeDataPages() {
	foreach (metaPages; MinMetaPages .. ChunkPageCount) {
		auto dataPages = ChunkPageCount - metaPages;
		auto runDescEnd = computeRunDescEnd(dataPages);
		auto requiredMetaPages = ((runDescEnd - 1) >> LgPageSize) + 1;

		if (requiredMetaPages <= metaPages) {
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
