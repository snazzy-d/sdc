module d.gc.rtree;

import d.gc.base;
import d.gc.spec;

import d.sync.atomic;

import sdc.intrinsics;

static assert(LgAddressSpace <= 48, "Address space too large!");

enum HighInsignificantBits = 8 * PointerSize - LgAddressSpace;
enum SignificantBits = LgAddressSpace - LgPageSize;

struct Level {
	uint bits;
	uint shift;

	this(uint bits, uint shift) {
		this.bits = bits;
		this.shift = shift;
	}
}

immutable Level[2] Levels =
	[Level(SignificantBits / 2, LgAddressSpace - SignificantBits / 2),
	 Level(SignificantBits / 2 + SignificantBits % 2, LgPageSize)];

enum Level0Size = size_t(1) << Levels[0].bits;
enum Level1Size = size_t(1) << Levels[1].bits;

enum Level0Align = size_t(1) << Levels[0].shift;
enum Level0Mask = Level0Size - 1;

static assert((Level0Mask & BlockPointerMask) == 0,
              "Cannot pack block pointer and level 0 key in one pointer!");

struct RTree(T) {
private:
	Node[Level0Size] nodes;

	import d.sync.mutex;
	Mutex initMutex;

	alias Cache = RTreeCache!T;
	alias Leaves = shared(Leaf[Level1Size])*;

	struct Leaf {
	private:
		Atomic!ulong data;

	public:
		void store(T value) shared {
			data.store(value.toLeafPayload());
		}

		auto load() shared {
			return T(data.load());
		}
	}

	struct Node {
	private:
		Atomic!size_t data;

	public:
		auto getLeaves() shared {
			return cast(Leaves) data.load();
		}
	}

public:
	shared(Leaf)* get(ref Cache cache, void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaves = getLeaves(cache, address);
		if (leaves is null) {
			return null;
		}

		return &(*leaves)[subKey(address, 1)];
	}

	bool set(ref Cache cache, void* address, T value,
	         ref shared Base base) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaf = getOrAllocate(cache, address, base);
		if (unlikely(leaf is null)) {
			return false;
		}

		leaf.store(value);
		return true;
	}

	bool setRange(ref Cache cache, void* address, uint pages, T value,
	              ref shared Base base) shared {
		auto start = address;
		auto stop = start + pages * PageSize;

		// FIXME: in contract.
		assert(isValidAddress(start));
		assert(isValidAddress(stop));

		auto ptr = start;
		while (ptr < stop) {
			auto leaves = getOrAllocateLeaves(cache, ptr, base);
			if (unlikely(leaves is null)) {
				return false;
			}

			import d.gc.util;
			auto nextPtr = alignUp(ptr + 1, Level0Align);
			auto key1 = subKey(ptr, 1);

			auto subStop = stop < nextPtr ? stop : nextPtr;
			while (ptr < subStop) {
				(*leaves)[key1++].store(value);
				ptr += PageSize;
				value = value.next();
			}
		}

		return true;
	}

	void clear(ref Cache cache, void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaf = get(cache, address);
		if (leaf !is null) {
			leaf.store(T(0));
		}
	}

	void clearRange(ref Cache cache, void* address, uint pages) shared {
		auto start = address;
		auto stop = address + pages * PageSize;

		// FIXME: in contract.
		assert(isValidAddress(start));
		assert(isValidAddress(stop));

		auto ptr = start;
		while (ptr < stop) {
			import d.gc.util;
			auto nextPtr = alignUp(ptr + 1, Level0Align);
			assert(subKey(nextPtr, 0) == subKey(ptr, 0) + 1);

			auto leaves = getLeaves(cache, ptr);
			if (leaves is null) {
				ptr = nextPtr;
				continue;
			}

			auto key1 = subKey(ptr, 1);

			// If we need to clear the whole page, do so via purging.
			// XXX: We might want to do it for smaller runs, but this is
			// more complicated as the alternative path requires atomic ops.
			if (key1 == 0 && stop >= nextPtr) {
				import d.gc.memmap;
				pages_purge(cast(void*) leaves.ptr, typeof(*leaves).sizeof);

				ptr = nextPtr;
				continue;
			}

			auto subStop = stop < nextPtr ? stop : nextPtr;
			while (ptr < subStop) {
				(*leaves)[key1++].store(T(0));
				ptr += PageSize;
			}
		}
	}

private:
	shared(Leaf)* getOrAllocate(ref Cache cache, void* address,
	                            ref shared Base base) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaves = getOrAllocateLeaves(cache, address, base);
		if (unlikely(leaves is null)) {
			return null;
		}

		return &(*leaves)[subKey(address, 1)];
	}

	auto getLeaves(ref Cache cache, void* address) shared {
		return getLeavesImpl!false(cache, address, null);
	}

	auto getOrAllocateLeaves(ref Cache cache, void* address,
	                         ref shared Base base) shared {
		return getLeavesImpl!true(cache, address, &base);
	}

	auto getLeavesImpl(bool Allocates)(ref Cache cache, void* address,
	                                   shared(Base)* base) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto key0 = subKey(address, 0);
		auto leaves = cache.lookup(key0);
		if (likely(leaves !is null)) {
			assert(leaves is nodes[key0].getLeaves(),
			       "The cache appears to be corrupted!");
			return leaves;
		}

		leaves = nodes[key0].getLeaves();
		if (Allocates && unlikely(leaves is null)) {
			leaves = allocateLeaves(*base, address, key0);
		}

		if (unlikely(leaves is null)) {
			return null;
		}

		cache.update(key0, leaves);
		return leaves;
	}

	auto allocateLeaves(ref shared Base base, void* address,
	                    size_t key0) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));
		assert(subKey(address, 0) == key0);

		// Note: We could use a CAS loop instead of using a mutex.
		// It's not clear if there is a real benefit.
		initMutex.lock();
		scope(exit) initMutex.unlock();

		auto leaves = nodes[key0].getLeaves();
		if (leaves !is null) {
			return leaves;
		}

		leaves = cast(Leaves) base.reserveAddressSpace(typeof(*leaves).sizeof);
		nodes[key0].data.store(cast(size_t) leaves, MemoryOrder.Relaxed);
		return leaves;
	}
}

struct RTreeCache(T) {
private:
	enum L1Size = 16;
	enum L2Size = 8;

	alias Leaves = RTree!T.Leaves;

	struct CacheEntry {
		size_t data;

		this(size_t key, Leaves leaves) {
			this(key, cast(size_t) leaves);
		}

		this(size_t key, size_t leaves) {
			assert((key & Level0Mask) == key, "Invalid level 0 key!");
			assert((leaves & BlockPointerMask) == leaves,
			       "Improperly aligned Leaves!");

			data = leaves | key;
		}

		@property
		auto key() const {
			return data & Level0Mask;
		}

		@property
		auto leaves() const {
			return cast(Leaves) (data & BlockPointerMask);
		}
	}

	CacheEntry[L1Size] l1;
	CacheEntry[L2Size] l2;

	Leaves lookup(size_t key) {
		assert((key & Level0Mask) == key, "Invalid key!");

		auto slot = key % L1Size;
		auto e = l1[slot];

		if (likely(e.key == key)) {
			return e.leaves;
		}

		// If we hit in the L2, we promote that entry to L1.
		auto c = l2[0];
		if (likely(c.key == key)) {
			l2[0] = e;

			l1[slot] = c;
			return c.leaves;
		}

		// If possible, move the position in the L2 up by 1.
		foreach (i; 1 .. L2Size) {
			c = l2[i];
			if (likely(c.key == key)) {
				l2[i] = l2[i - 1];
				l2[i - 1] = e;

				l1[slot] = c;
				return c.leaves;
			}
		}

		return null;
	}

	void update(size_t key, Leaves leaves) {
		assert((key & Level0Mask) == key, "Invalid key!");

		auto slot = key % L1Size;
		auto e = l1[slot];

		l1[slot] = CacheEntry(key, leaves);
		if (unlikely(e.leaves is null)) {
			return;
		}

		// We had data in l1, push it in l2.
		memmove(&l2[1], l2.ptr, CacheEntry.sizeof * (L2Size - 1));
		l2[0] = e;
	}
}

private:

ulong toLeafPayload(ulong x) {
	// So that we can store integrals in the tree.
	return x;
}

ulong next(ulong x) {
	// So that we can store integrals in the tree.
	return x + 1;
}

bool isValidAddress(void* address) {
	auto a = cast(size_t) address;
	return (a & PagePointerMask) == a;
}

unittest isValidAddress {
	static checkIsValid(size_t value, bool expected) {
		assert(isValidAddress(cast(void*) value) == expected);
	}

	checkIsValid(0x56789abcd000, true);
	checkIsValid(0x789abcdef000, true);
	checkIsValid(0xfedcba987000, true);

	checkIsValid(0, true);
	checkIsValid(1, false);
	checkIsValid(-1, false);
	checkIsValid(12345, false);
	checkIsValid(0xfffffffff000, true);
	checkIsValid(0x1000000000000, false);
	checkIsValid(0xfffffffffffff000, false);

	foreach (i; 0 .. SignificantBits) {
		auto address = PageSize << i;
		checkIsValid(address - 1, false);
		checkIsValid(address, true);
		checkIsValid(address + 1, false);
	}

	checkIsValid(PageSize << SignificantBits, false);
}

static subKey(void* ptr, uint level) {
	// FIXME: in contract.
	assert(isValidAddress(ptr), "Invalid ptr!");

	auto key = cast(size_t) ptr;
	auto shift = Levels[level].shift;
	auto mask = (size_t(1) << Levels[level].bits) - 1;

	return (key >> shift) & mask;
}

unittest subKey {
	auto p = cast(void*) 0x56789abcd000;
	assert(subKey(p, 0) == 0x159e2);
	assert(subKey(p, 1) == 0x1abcd);

	p = cast(void*) 0x789abcdef000;
	assert(subKey(p, 0) == 0x1e26a);
	assert(subKey(p, 1) == 0x3cdef);

	p = cast(void*) 0xfedcba987000;
	assert(subKey(p, 0) == 0x3fb72);
	assert(subKey(p, 1) == 0x3a987);
}

unittest spawn_leaves {
	shared Base base;
	scope(exit) base.clear();

	static shared RTree!ulong rt;
	RTreeCache!ulong cache;

	auto p = cast(void*) 0x56789abcd000;
	assert(rt.nodes[0x159e2].getLeaves() is null);
	assert(rt.get(cache, p) is null);
	assert(rt.nodes[0x159e2].getLeaves() is null);

	// Allocate a leaf.
	auto leaf = rt.getOrAllocate(cache, p, base);
	assert(rt.nodes[0x159e2].getLeaves() !is null);

	// The leaf itself is null.
	assert(leaf !is null);
	assert(leaf.load() == 0);

	// Now we return that leaf.
	assert(rt.getOrAllocate(cache, p, base) is leaf);
	assert(rt.get(cache, p) is leaf);

	// The leaf is where we epxect it to be.
	auto leaves = rt.nodes[0x159e2].getLeaves();
	assert(&(*leaves)[0x1abcd] is leaf);
}

unittest get_set_clear {
	shared Base base;
	scope(exit) base.clear();

	static shared RTree!ulong rt;
	RTreeCache!ulong cache;

	// Add one page descriptor in the tree.
	auto ptr0 = cast(void*) 0x56789abcd000;
	auto v0 = 0x0123456789abcdef;

	assert(rt.get(cache, ptr0) is null);
	assert(rt.set(cache, ptr0, v0, base));
	assert(rt.get(cache, ptr0) !is null);
	assert(rt.get(cache, ptr0).load() == v0);

	// Add a second page descriptor in the tree.
	auto ptr1 = cast(void*) 0x789abcdef000;
	auto v1 = 0x0123456789abcdef;

	assert(rt.get(cache, ptr1) is null);
	assert(rt.set(cache, ptr1, v1, base));
	assert(rt.get(cache, ptr1) !is null);
	assert(rt.get(cache, ptr1).load() == v1);

	// This did not affect the first insertion.
	assert(rt.get(cache, ptr0).load() == v0);

	// However, we can rewrite existing entries.
	assert(rt.set(cache, ptr0, v1, base));
	assert(rt.set(cache, ptr1, v0, base));

	assert(rt.get(cache, ptr0).load() == v1);
	assert(rt.get(cache, ptr1).load() == v0);

	// Now we can clear.
	rt.clear(cache, ptr0);
	assert(rt.get(cache, ptr0).load() == 0);
	assert(rt.get(cache, ptr1).load() == v0);

	rt.clear(cache, ptr1);
	assert(rt.get(cache, ptr0).load() == 0);
	assert(rt.get(cache, ptr1).load() == 0);

	// We can also clear unmapped addresses.
	auto ptr2 = cast(void*) 0xfedcba987000;
	assert(rt.get(cache, ptr2) is null);
	rt.clear(cache, ptr2);
	assert(rt.get(cache, ptr2) is null);
}

unittest set_clear_range {
	shared Base base;
	scope(exit) base.clear();

	static shared RTree!ulong rt;
	RTreeCache!ulong cache;

	// Add one page descriptor in the tree.
	auto ptr0 = cast(void*) 0x56789abcd000;
	auto v0 = 0x0123456789abcdef;

	assert(rt.get(cache, ptr0) is null);
	assert(rt.setRange(cache, ptr0, 1, v0, base));
	assert(rt.get(cache, ptr0) !is null);
	assert(rt.get(cache, ptr0).load() == v0);

	// Add a second page descriptor in the tree.
	auto ptr1 = cast(void*) 0x00003ffff000;
	auto v1 = 0x0123456789abcdef;

	assert(rt.get(cache, ptr1) is null);
	assert(rt.setRange(cache, ptr1, 1234, v1, base));
	assert(rt.get(cache, ptr1) !is null);
	assert(rt.get(cache, ptr1).load() == v1);

	foreach (i; 0 .. 1234) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(cache, ptr) !is null);
		assert(rt.get(cache, ptr).load() == v);
	}

	rt.clearRange(cache, ptr1, 910);
	foreach (i; 0 .. 910) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(cache, ptr).load() == 0);
	}

	foreach (i; 910 .. 1234) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(cache, ptr) !is null);
		assert(rt.get(cache, ptr).load() == v);
	}

	rt.clearRange(cache, ptr1, 345678);
	foreach (i; 0 .. 262145) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(cache, ptr).load() == 0);
	}

	foreach (i; 262145 .. 345678) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(cache, ptr) is null);
	}
}

unittest rtree_cache {
	shared Base base;
	scope(exit) base.clear();

	static shared RTree!ulong rt;
	RTreeCache!ulong cache;

	enum L1Size = RTreeCache!ulong.L1Size;
	enum L2Size = RTreeCache!ulong.L2Size;

	auto checkL1Cache(void* ptr, uint expectedSlot) {
		auto key = subKey(ptr, 0);
		auto slot = key % L1Size;

		assert(slot == expectedSlot);
		assert(cache.l1[slot].key == key);
		assert(cache.l1[slot].leaves is rt.nodes[key].getLeaves());
	}

	auto checkL2Cache(void* ptr, uint slot) {
		auto key = subKey(ptr, 0);

		assert(cache.l2[slot].key == key);
		assert(cache.l2[slot].leaves is rt.nodes[key].getLeaves());
	}

	// Add one page descriptor in the tree.
	auto ptr0 = cast(void*) 0x56781abcd000;
	auto v0 = 0x0123456789abcdef;

	foreach (i; 0 .. L1Size) {
		auto ptr = ptr0 + i * Level0Align;
		assert(rt.set(cache, ptr, v0, base));
		checkL1Cache(ptr, i);

		// Nothing spills into L2.
		foreach (j; 0 .. L2Size) {
			assert(cache.l2[j].leaves is null);
		}
	}

	enum RepeatOffset = L1Size * Level0Align;
	auto ptr1 = ptr0 + RepeatOffset;

	// Collisions push entries into L2.
	foreach (i; 0 .. L1Size) {
		auto ptr = ptr1 + i * Level0Align;

		assert(rt.set(cache, ptr, v0, base));
		checkL1Cache(ptr, i);

		// Previous pointers are pushed onto L2.
		import d.gc.util;
		foreach (j; 0 .. min(i + 1, L2Size)) {
			auto evictedPtr = ptr0 + (i - j) * Level0Align;
			checkL2Cache(evictedPtr, j);
		}

		// No extra spills into L2.
		foreach (j; i + 1 .. L2Size) {
			assert(cache.l2[j].leaves is null);
		}
	}

	auto savedL2 = cache.l2;
	auto checkSavedL2(uint shift) {
		foreach (i; 0 .. L2Size - shift) {
			auto s = savedL2[i];
			auto c = cache.l2[i + shift];

			assert(s.key == c.key);
			assert(s.leaves is c.leaves);
		}
	}

	// Collide in slot 0 causes the colliding element to be
	// placed in the first slot of the L2 and all other L2
	// elements get shifted up by 1.
	assert(rt.set(cache, ptr0, v0, base));
	checkL1Cache(ptr0, 0);
	checkL2Cache(ptr1, 0);
	checkSavedL2(1);

	// Matching the first slot in L2 causes a swap.
	assert(rt.set(cache, ptr1, v0, base));
	checkL1Cache(ptr1, 0);
	checkL2Cache(ptr0, 0);
	checkSavedL2(1);

	// Evict elements to push ptr0 into the last slot.
	savedL2 = cache.l2;
	foreach (i; 1 .. L2Size) {
		auto ptr = ptr0 + i * Level0Align;

		assert(rt.set(cache, ptr, v0, base));
		checkL1Cache(ptr, i);
		checkL2Cache(ptr0, i);
		checkSavedL2(i);
	}

	// Matching in L2 promotes the element to L1 and move the
	// slots up by 1 for the demoted element.
	savedL2 = cache.l2;
	foreach (i; 1 .. L2Size) {
		auto evictedPtr = ptr0 + (i & 0x01) * RepeatOffset;
		auto ptr = cast(void*) ((cast(size_t) evictedPtr) ^ RepeatOffset);

		assert(rt.set(cache, ptr, v0, base));
		checkL1Cache(ptr, 0);

		auto slot = L2Size - i - 1;
		checkL2Cache(evictedPtr, slot);

		// Elements before the slot are unaffected.
		foreach (j; 0 .. slot) {
			auto s = savedL2[j];
			auto c = cache.l2[j];

			assert(s.key == c.key);
			assert(s.leaves is c.leaves);
		}

		// Elements after the slot are moved up by 1.
		foreach (j; slot .. L2Size - 1) {
			auto s = savedL2[j];
			auto c = cache.l2[j + 1];

			assert(s.key == c.key);
			assert(s.leaves is c.leaves);
		}
	}
}
