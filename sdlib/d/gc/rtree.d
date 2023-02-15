module d.gc.rtree;

import d.gc.spec;

import d.sync.atomic;

static assert(LgAddressSpace <= 48, "Address space too large!");

enum HighInsignificantBits = 8 * PointerSize - LgAddressSpace;
enum SignificantBits = LgAddressSpace - LgPageSize;

struct Level {
	uint bits;
	uint cumulativeBits;

	this(uint bits, uint cumulativeBits) {
		this.bits = bits;
		this.cumulativeBits = cumulativeBits;
	}
}

immutable Level[2] Levels = [
	Level(SignificantBits / 2, HighInsignificantBits + SignificantBits / 2),
	Level(SignificantBits / 2 + SignificantBits % 2,
	      HighInsignificantBits + SignificantBits),
];

enum Level0Size = 1UL << Levels[0].bits;
enum Level1Size = 1UL << Levels[1].bits;

struct RadixTree {
private:
	import d.gc.base;
	Base* base;

	import d.sync.mutex;
	Mutex initMutex;

	Node[Level0Size] nodes;

public:
	shared(Leaf)* get(void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaves = getLeaves(address);
		if (leaves is null) {
			return null;
		}

		return &(*leaves)[subKey(address, 1)];
	}

	shared(Leaf)* getOrAllocate(void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaves = getOrAllocateLeaves(address);
		if (leaves is null) {
			return null;
		}

		return &(*leaves)[subKey(address, 1)];
	}

	bool set(void* address, PageDescriptor pd) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaf = getOrAllocate(address);
		if (leaf is null) {
			return false;
		}

		leaf.store(pd);
		return true;
	}

	void clear(void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaf = get(address);
		if (leaf !is null) {
			leaf.store(PageDescriptor(0));
		}
	}

private:
	static isValidAddress(void* address) {
		auto mask1 = size_t(-1) >> HighInsignificantBits;
		auto mask2 = size_t(-1) << LgPageSize;

		auto a = cast(size_t) address;
		return (a & mask1 & mask2) == a;
	}

	static subKey(void* ptr, uint level) {
		auto key = cast(size_t) ptr;
		auto shift = 8 * PointerSize - Levels[level].cumulativeBits;
		auto mask = (size_t(1) << Levels[level].bits) - 1;

		return (key >> shift) & mask;
	}

	auto getLeaves(void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto key0 = subKey(address, 0);
		return nodes[key0].getLeaves();
	}

	auto getOrAllocateLeaves(void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto key0 = subKey(address, 0);
		auto leaves = nodes[key0].getLeaves();
		if (leaves !is null) {
			return leaves;
		}

		// Note: We could use a CAS loop instead of using a mutex.
		// It's not clear if there is a real benefit.
		initMutex.lock();
		scope(exit) initMutex.unlock();

		leaves = nodes[key0].getLeaves();
		if (leaves !is null) {
			return leaves;
		}

		leaves =
			cast(typeof(leaves)) base.alloc(typeof(*leaves).sizeof, CacheLine);
		nodes[key0].data.store(cast(size_t) leaves, MemoryOrder.Relaxed);
		return leaves;
	}
}

private:

struct Node {
private:
	Atomic!size_t data;

public:
	auto getLeaves() shared {
		return cast(shared(Leaf[Level1Size])*) data.load();
	}
}

struct Leaf {
private:
	Atomic!ulong data;

public:
	void store(PageDescriptor pd) shared {
		data.store(pd.data);
	}

	auto load() shared {
		return PageDescriptor(data.load());
	}
}

struct PageDescriptor {
private:
	ulong data;

	this(ulong data) {
		this.data = data;
	}

public:
	@property
	bool isSlab() const {
		return (data & 0x01) != 0;
	}
}

unittest isValidAddress {
	static checkIsValid(size_t value, bool expected) {
		assert(RadixTree.isValidAddress(cast(void*) value) == expected);
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
		auto addr = PageSize << i;
		checkIsValid(addr - 1, false);
		checkIsValid(addr, true);
		checkIsValid(addr + 1, false);
	}

	checkIsValid(PageSize << SignificantBits, false);
}

unittest hash {
	auto p = cast(void*) 0x56789abcd000;
	assert(RadixTree.subKey(p, 0) == 0x159e2);
	assert(RadixTree.subKey(p, 1) == 0x1abcd);

	p = cast(void*) 0x789abcdef000;
	assert(RadixTree.subKey(p, 0) == 0x1e26a);
	assert(RadixTree.subKey(p, 1) == 0x3cdef);

	p = cast(void*) 0xfedcba987000;
	assert(RadixTree.subKey(p, 0) == 0x3fb72);
	assert(RadixTree.subKey(p, 1) == 0x3a987);
}

unittest spawn_leaves {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	static shared RadixTree rt;
	rt.base = &base;

	auto p = cast(void*) 0x56789abcd000;
	assert(rt.nodes[0x159e2].getLeaves() is null);
	assert(rt.get(p) is null);
	assert(rt.nodes[0x159e2].getLeaves() is null);

	// Allocate a leaf.
	auto leaf = rt.getOrAllocate(p);
	assert(rt.nodes[0x159e2].getLeaves() !is null);

	// The leaf itself is null.
	assert(leaf !is null);
	assert(leaf.data.load() == 0);

	// Now we return that leaf.
	assert(rt.getOrAllocate(p) is leaf);
	assert(rt.get(p) is leaf);

	// The leaf is where we epxect it to be.
	auto leaves = rt.nodes[0x159e2].getLeaves();
	assert(&(*leaves)[0x1abcd] is leaf);
}

unittest get_set_clear {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	static shared RadixTree rt;
	rt.base = &base;

	// Add one page descriptor in the tree.
	auto ptr0 = cast(void*) 0x56789abcd000;
	auto pd0 = PageDescriptor(0x0123456789abcdef);

	assert(rt.get(ptr0) is null);
	assert(rt.set(ptr0, pd0));
	assert(rt.get(ptr0) !is null);
	assert(rt.get(ptr0).load().data == pd0.data);

	// Add a second page descriptor in the tree.
	auto ptr1 = cast(void*) 0x789abcdef000;
	auto pd1 = PageDescriptor(0x0123456789abcdef);

	assert(rt.get(ptr1) is null);
	assert(rt.set(ptr1, pd1));
	assert(rt.get(ptr1) !is null);
	assert(rt.get(ptr1).load().data == pd1.data);

	// This did not affect the first insertion.
	assert(rt.get(ptr0).load().data == pd0.data);

	// However, we can rewrite existing entries.
	assert(rt.set(ptr0, pd1));
	assert(rt.set(ptr1, pd0));

	assert(rt.get(ptr0).load().data == pd1.data);
	assert(rt.get(ptr1).load().data == pd0.data);

	// Now we can clear.
	rt.clear(ptr0);
	assert(rt.get(ptr0).load().data == 0);
	assert(rt.get(ptr1).load().data == pd0.data);

	rt.clear(ptr1);
	assert(rt.get(ptr0).load().data == 0);
	assert(rt.get(ptr1).load().data == 0);

	// We can also clear unmapped addresses.
	auto ptr2 = cast(void*) 0xfedcba987000;
	assert(rt.get(ptr2) is null);
	rt.clear(ptr2);
	assert(rt.get(ptr2) is null);
}
