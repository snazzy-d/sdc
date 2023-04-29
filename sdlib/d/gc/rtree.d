module d.gc.rtree;

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

struct RTree(T) {
private:
	import d.gc.base;
	shared(Base)* base;

	import d.sync.mutex;
	Mutex initMutex;

	struct Node {
	private:
		Atomic!size_t data;

	public:
		auto getLeaves() shared {
			return cast(shared(Leaf[Level1Size])*) data.load();
		}
	}

	Node[Level0Size] nodes;

public:
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
		if (unlikely(leaves is null)) {
			return null;
		}

		return &(*leaves)[subKey(address, 1)];
	}

	bool set(void* address, T value) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaf = getOrAllocate(address);
		if (unlikely(leaf is null)) {
			return false;
		}

		leaf.store(value);
		return true;
	}

	bool setRange(void* address, size_t size, T value) shared {
		auto start = address;
		auto stop = start + size;

		// FIXME: in contract.
		assert(isValidAddress(start));
		assert(isValidAddress(stop));

		auto ptr = start;
		while (ptr < stop) {
			auto leaves = getOrAllocateLeaves(ptr);
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

	void clear(void* address) shared {
		// FIXME: in contract.
		assert(isValidAddress(address));

		auto leaf = get(address);
		if (leaf !is null) {
			leaf.store(T(0));
		}
	}

	void clearRange(void* address, size_t size) shared {
		auto start = address;
		auto stop = address + size;

		// FIXME: in contract.
		assert(isValidAddress(start));
		assert(isValidAddress(stop));

		auto ptr = start;
		while (ptr < stop) {
			import d.gc.util;
			auto nextPtr = alignUp(ptr + 1, Level0Align);
			assert(subKey(nextPtr, 0) == subKey(ptr, 0) + 1);

			auto leaves = getLeaves(ptr);
			if (leaves is null) {
				import d.gc.util;
				ptr = nextPtr;
				continue;
			}

			auto key1 = subKey(ptr, 1);

			auto subStop = stop < nextPtr ? stop : nextPtr;
			while (ptr < subStop) {
				(*leaves)[key1++].store(T(0));
				ptr += PageSize;
			}
		}
	}

private:
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

		leaves = cast(typeof(leaves))
			base.reserveAddressSpace(typeof(*leaves).sizeof);
		nodes[key0].data.store(cast(size_t) leaves, MemoryOrder.Relaxed);
		return leaves;
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
	enum Mask = AddressSpace - PageSize;

	auto a = cast(size_t) address;
	return (a & Mask) == a;
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
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	static shared RTree!ulong rt;
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
	assert(leaf.load() == 0);

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

	static shared RTree!ulong rt;
	rt.base = &base;

	// Add one page descriptor in the tree.
	auto ptr0 = cast(void*) 0x56789abcd000;
	auto v0 = 0x0123456789abcdef;

	assert(rt.get(ptr0) is null);
	assert(rt.set(ptr0, v0));
	assert(rt.get(ptr0) !is null);
	assert(rt.get(ptr0).load() == v0);

	// Add a second page descriptor in the tree.
	auto ptr1 = cast(void*) 0x789abcdef000;
	auto v1 = 0x0123456789abcdef;

	assert(rt.get(ptr1) is null);
	assert(rt.set(ptr1, v1));
	assert(rt.get(ptr1) !is null);
	assert(rt.get(ptr1).load() == v1);

	// This did not affect the first insertion.
	assert(rt.get(ptr0).load() == v0);

	// However, we can rewrite existing entries.
	assert(rt.set(ptr0, v1));
	assert(rt.set(ptr1, v0));

	assert(rt.get(ptr0).load() == v1);
	assert(rt.get(ptr1).load() == v0);

	// Now we can clear.
	rt.clear(ptr0);
	assert(rt.get(ptr0).load() == 0);
	assert(rt.get(ptr1).load() == v0);

	rt.clear(ptr1);
	assert(rt.get(ptr0).load() == 0);
	assert(rt.get(ptr1).load() == 0);

	// We can also clear unmapped addresses.
	auto ptr2 = cast(void*) 0xfedcba987000;
	assert(rt.get(ptr2) is null);
	rt.clear(ptr2);
	assert(rt.get(ptr2) is null);
}

unittest set_clear_range {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	static shared RTree!ulong rt;
	rt.base = &base;

	// Add one page descriptor in the tree.
	auto ptr0 = cast(void*) 0x56789abcd000;
	auto v0 = 0x0123456789abcdef;

	assert(rt.get(ptr0) is null);
	assert(rt.setRange(ptr0, PageSize, v0));
	assert(rt.get(ptr0) !is null);
	assert(rt.get(ptr0).load() == v0);

	// Add a second page descriptor in the tree.
	auto ptr1 = cast(void*) 0x00003ffff000;
	auto v1 = 0x0123456789abcdef;

	assert(rt.get(ptr1) is null);
	assert(rt.setRange(ptr1, 1234 * PageSize, v1));
	assert(rt.get(ptr1) !is null);
	assert(rt.get(ptr1).load() == v1);

	foreach (i; 0 .. 1234) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(ptr) !is null);
		assert(rt.get(ptr).load() == v);
	}

	rt.clearRange(ptr1, 910 * PageSize);
	foreach (i; 0 .. 910) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(ptr).load() == 0);
	}

	foreach (i; 910 .. 1234) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(ptr) !is null);
		assert(rt.get(ptr).load() == v);
	}

	rt.clearRange(ptr1, 345678 * PageSize);
	foreach (i; 0 .. 262145) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(ptr).load() == 0);
	}

	foreach (i; 262145 .. 345678) {
		auto v = v1 + i;
		auto ptr = ptr1 + i * PageSize;

		assert(rt.get(ptr) is null);
	}
}
