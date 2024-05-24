module d.gc.emap;

import d.gc.base;
import d.gc.extent;
import d.gc.rtree;
import d.gc.spec;
import d.gc.util;

import sdc.intrinsics;

shared ExtentMap gExtentMap;

alias ExtentMapCache = RTreeCache!PageDescriptor;

struct ExtentMap {
private:
	RTree!PageDescriptor tree;

public:
	PageDescriptor lookup(ref ExtentMapCache cache, void* address) shared {
		auto leaf = tree.get(cache, address);
		return leaf is null ? PageDescriptor(0) : leaf.load();
	}

	BlockExtentMap blockLookup(ref ExtentMapCache cache, void* block) shared {
		assert(isAligned(block, BlockSize), "Invalid block address!");
		return BlockExtentMap(block, tree.get(cache, block));
	}

	bool map(ref shared Base base, ref ExtentMapCache cache, void* address,
	         uint pages, PageDescriptor pd) shared {
		return tree.setRange(cache, address, pages, pd, base);
	}

	void clear(ref ExtentMapCache cache, void* address, uint pages) shared {
		tree.clearRange(cache, address, pages);
	}
}

/**
 * It might be puzzling why we would want to have a cache for the ExtentMap.
 * After all, we are trading one lookup in the cache vs one lookup in the
 * base level of the ExtentMap, so it's not obvious where the win is.
 *
 * Each entry in the cache maps to 1GB of address space, os we expect the
 * hit rate in the cache to be close to 100% . Realistically, most applications
 * won't use more than 16GB of address space, and for these which do, you'd
 * still need scattered access access accross this huge address space for the
 * hit rate to degrade, in which case the performance of this cache is unlikely
 * to be of any significant importance.
 *
 * Each page that we expect to be hot in the GC is one less page that can be hot
 * for the applciation itself. So in general, we try to avoid touching memory
 * when we don't need to. We know the thread cache has to be hot as it is the
 * entry point for every GC operation. Adding this cache in the thread cache
 * ensures that we can have a close to 100% hit rate by only touching memory
 * that has to be hot no matter what. This turns out to be a won in practice.
 *
 * If later on we want to support system with more than 48 bits of address
 * space, then we will need an extent map with 3 levels, and this cache will
 * avoid 2 lookups insteaf of 1, which is much more obvious win.
 */
struct CachedExtentMap {
private:
	ExtentMapCache cache;
	shared(ExtentMap)* emap;
	shared(Base)* base;

public:
	this(shared(ExtentMap)* emap, shared(Base)* base) {
		this.emap = emap;
		this.base = base;
	}

	PageDescriptor lookup(void* address) {
		return emap.lookup(cache, address);
	}

	BlockExtentMap blockLookup(void* address) {
		assert(isAligned(address, BlockSize), "Invalid block address!");

		return emap.blockLookup(cache, address);
	}

	bool map(void* address, uint pages, PageDescriptor pd) {
		return emap.map(*base, cache, address, pages, pd);
	}

	bool remap(Extent* extent, ExtentClass ec) {
		auto pd = PageDescriptor(extent, ec);
		return map(extent.address, extent.npages, pd);
	}

	bool remap(Extent* extent) {
		// FIXME: in contract.
		assert(!extent.isSlab(), "Extent is a slab!");
		return remap(extent, ExtentClass.large());
	}

	void clear(void* address, uint pages) {
		emap.clear(cache, address, pages);
	}

	void clear(Extent* extent) {
		clear(extent.address, extent.npages);
	}
}

struct PageDescriptor {
private:
	/**
	 * The extent itself is 7 bits aligned and the address space 48 bits.
	 * This leaves us with the low 7 bits and the high 16 bits of the extent's
	 * pointer to play with.
	 * 
	 * We use these bits to pack the following data in the descriptor:
	 *  - i: The index within the extent, 4 bits truncated.
	 *  - a: The arena index.
	 *  - e: The extent class.
	 *  - p: The extent pointer.
	 * 
	 * 63    56 55    48 47    40 39             8 7      0
	 * iiiiaaaa aaaaaaaa pppppppp [extent pointer] p.eeeeee
	 */
	ulong data;

package:
	this(ulong data) {
		this.data = data;
	}

public:
	this(Extent* extent, ExtentClass ec) {
		// FIXME: in contract.
		assert(isAligned(extent, ExtentAlign), "Invalid Extent alignment!");
		assert(extent.extentClass.data == ec.data, "Invalid ExtentClass!");

		data = ec.data;
		data |= cast(size_t) extent;
		data |= ulong(extent.arenaIndex) << 48;
	}

	this(Extent* extent) {
		// FIXME: in contract.
		assert(!extent.isSlab(), "Extent is a slab!");
		this(extent, ExtentClass.large());
	}

	auto toLeafPayload() const {
		return data;
	}

	@property
	Extent* extent() {
		return cast(Extent*) (data & ExtentMask);
	}

	@property
	uint index() const {
		// FIXME: in contract.
		assert(isSlab(), "Index is only supported for slabs!");

		return data >> 60;
	}

	auto next(uint pages = 1) const {
		auto increment = ulong(pages) << 60;
		return PageDescriptor(data + increment);
	}

	/**
	 * Arena.
	 */
	@property
	uint arenaIndex() const {
		return (data >> 48) & ArenaMask;
	}

	@property
	bool containsPointers() const {
		return (arenaIndex & 0x01) != 0;
	}

	@property
	auto arena() const {
		import d.gc.arena;
		return Arena.getInitialized(arenaIndex);
	}

	/**
	 * Slab features.
	 */
	@property
	auto extentClass() const {
		return ExtentClass(data & ExtentClass.Mask);
	}

	bool isSlab() const {
		auto ec = extentClass;
		return ec.isSlab();
	}

	auto computeOffset(const void* ptr) const {
		assert(isSlab(), "Computing offset is only supported on slabs!");

		return index * PageSize + alignDownOffset(ptr, PageSize);
	}
}

struct BlockExtentMap {
private:
	void* block;
	shared(Leaf[PagesInBlock])* leaves;

	alias Leaf = RTree!PageDescriptor.Leaf;

public:
	this(void* block, shared(Leaf)* leaf) {
		assert(isAligned(block, BlockSize), "Invalid block address!");
		assert(leaf !is null, "Unmapped block!");

		this.block = block;
		this.leaves = cast(shared(Leaf[PagesInBlock])*) leaf;
	}

	auto lookup(uint index) {
		assert(index < PagesInBlock, "Invalid index!");
		return (*leaves)[index].load();
	}
}

unittest ExtentMap {
	shared Base base;
	scope(exit) base.clear();

	static shared ExtentMap emapStorage;
	auto emap = CachedExtentMap(&emapStorage, &base);

	// We have not mapped anything.
	auto ptr = cast(void*) 0x56789abcd000;
	assert(emap.lookup(ptr).data == 0);

	auto slot = base.allocSlot();
	auto e = Extent.fromSlot(0, slot);
	e.at(ptr, 5, null);

	// Map a range.
	emap.remap(e);
	auto pd = PageDescriptor(e);

	auto end = ptr + e.size;
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
		pd = pd.next();
	}

	assert(emap.lookup(end).data == 0);

	// Clear a range.
	emap.clear(e);
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == 0);
	}

	auto ec = ExtentClass.slab(0);
	e.at(ptr, 5, null, ec);
	emap.remap(e, ec);
	pd = PageDescriptor(e, ec);

	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
		pd = pd.next();
	}

	emap.clear(e);

	// Shrink a range.
	e.at(ptr, 5, null, ec);
	emap.remap(e, ec);
	pd = PageDescriptor(e, ec);

	emap.clear(e.address + 3 * PageSize, 2);
	e.at(ptr, 3, null, ec);

	for (auto p = ptr; p < e.address + 3 * PageSize; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
		pd = pd.next();
	}

	for (auto p = e.address + 3 * PageSize; p < e.address + 5 * PageSize;
	     p += PageSize) {
		assert(emap.lookup(p).data == 0);
	}
}
