module d.gc.tbin;

import d.gc.arena;
import d.gc.emap;
import d.gc.sizeclass;
import d.gc.spec;

import sdc.intrinsics;

/**
 * Some thread cache configuration parameters.
 */
enum SlotsMultiplier = 2;
enum MaxCapacity = 200;
enum MinCapacity = 20;

enum ThreadBinCount = 2 * BinCount;

/**
 * The ThreadBin manages a cache associated with a given size class.
 * 
 * Instead of allocating one element a the time, we allocate several
 * and store them in the cache. This way, a thread can do mutliple
 * allocations before requiring a new round trip in the arena. Even
 * better, if the thread frees its slots, they are returned to the
 * cache and can be reused.
 * 
 * The cache is a buffer containing pointers organised as follow:
 * 
 * low address                                        high address
 * |----- stashed -----|----- available -----|----- cached -----|
 * ^                   ^                     ^      ^           ^
 * bottom              available             head   low water   top
 * 
 * Because the buffer is never larger than 64k, we can store exclusively
 * the lower 16-bits of all the pointer above except one. This ensures
 * that we do not use more cache than strictly required.
 * 
 * On a regular basis, we run a maintenance routine on the bins. During
 * that maintenance, we set the low water to the head of the cache. When
 * element are removed from the cache, the low water mark is also moved.
 * This ensures the maintenance routine can track the elements that
 * remained in the cache accorss runs and ensures they eventually get
 * purged.
 */
struct ThreadBin {
private:
	void** _head;

	ushort _top;
	ushort _low_water;
	ushort _available;
	ushort _bottom;

public:
	this(void*[] buffer) {
		_head = buffer.ptr;
		_bottom = current;
		_available = current;

		_head += buffer.length;
		_top = current;
		_low_water = current;
	}

	// Allocate without moving the low water mark.
	bool allocateEasy(ref void* ptr) {
		return allocateImpl!false(ptr);
	}

	// Allocate and move the low water mark if necessary.
	bool allocate(ref void* ptr) {
		return allocateImpl!true(ptr);
	}

	void refill(ref CachedExtentMap emap, shared(Arena)* arena,
	            ref ThreadBinState state, ubyte sizeClass, size_t slotSize) {
		_head =
			arena.batchAllocSmall(emap, sizeClass, _head, available, slotSize);
		state.refilled = true;
	}

	bool freeEasy(void* ptr) {
		if (unlikely(full)) {
			return false;
		}

		*(--_head) = ptr;
		return true;
	}

	void free(ref CachedExtentMap emap, PageDescriptor pd, void* ptr) {
		if (likely(freeEasy(ptr))) {
			return;
		}

		/**
		 * We do not have enough space in the bin, so start flushing.
		 * However, we do not want to flush all of it, as it would leave
		 * us without anything to allocate from.
		 * A high low water mark indicates a low allocation rate, so we
		 * flush more when the low water mark is high.
		 * 
		 * Note: We ensure that the low water mark never reaches 0.
		 *       It would make it look like this bin is high allocation.
		 */
		auto nretain = (nmax / 2) - (nlowWater / 4);
		flush(emap, nretain);
		auto success = freeEasy(ptr);
		assert(success, "Unable to free!");
	}

	void flush(ref CachedExtentMap emap) {
		flush(emap, 0);
	}

	void flush(ref CachedExtentMap emap, uint nretain) {
		if (nretain >= ncached) {
			return;
		}

		// We precompute all we need so we can work out of lowal variables.
		auto newHead = top;
		auto oldHead = _head;
		auto base = oldHead + nretain;

		auto nlw = nlowWater;
		auto nflush = ncached - nretain;
		assert(nflush <= ncached,
		       "Cannot flush more elements than are cached!");

		auto worklist = base[0 .. nflush];

		/**
		 * TODO: Statistically, a lot of the pointers are going to
		 *       be from the same slab. There are a number of
		 *       optimizations that can be done based on that fact.
		 *       We need a batch emap lookup facility.
		 */
		auto pds = cast(PageDescriptor*) alloca(nflush * PageDescriptor.sizeof);

		foreach (i, ptr; worklist) {
			import d.gc.util;
			auto aptr = alignDown(ptr, PageSize);
			pds[i] = emap.lookup(aptr);
		}

		// Actually do flush to the arenas.
		while (worklist.length > 0) {
			auto ndeferred = pds[0].arena.batchFree(emap, worklist, pds);
			worklist = base[0 .. ndeferred];
		}

		// Move the remaining items on top of the stack if necessary.
		if (nretain > 0) {
			auto src = base;
			while (src > oldHead) {
				*(--newHead) = *(--src);
			}
		}

		// Adjust bin markers to reflect the flush.
		_head = newHead;
		if (nretain < nlw) {
			_low_water = current;
		}

		/**
		 * FIXME: This shouldn't be necessary, but we currently have no way
		 *        to ensure the thread cache is not marked as part of the
		 *        regular TLS marking.
		 *        In turns, this means we are going to keep garbage alive
		 *        due to leftover pointers in there.
		 */
		auto ptr = bottom;
		while (ptr < newHead) {
			*(ptr++) = null;
		}
	}

private:
	@property
	ushort current() const {
		auto c = cast(size_t) _head;
		return c & ushort.max;
	}

	@property
	bool empty() const {
		return current == _top;
	}

	@property
	bool full() const {
		return current == _available;
	}

	@property
	void** top() const {
		return adjustHigher(_top);
	}

	@property
	void** lowWater() const {
		return adjustHigher(_low_water);
	}

	@property
	void** available() const {
		return adjustLower(_available);
	}

	@property
	void** bottom() const {
		return adjustLower(_bottom);
	}

	@property
	ushort ncached() const {
		return delta(current, _top) / PointerSize;
	}

	@property
	ushort nlowWater() const {
		return delta(_low_water, _top) / PointerSize;
	}

	@property
	ushort nstashed() const {
		return delta(_bottom, _available) / PointerSize;
	}

	@property
	ushort nmax() const {
		return delta(_bottom, _top) / PointerSize;
	}

	/**
	 * We "return" the pointer by ref and indicate success with a boolean.
	 * 
	 * We could return null in case of failure, but we never store null
	 * in the cache, and we don't want to cause a stall on success if
	 * the value wasn't in cache.
	 */
	bool allocateImpl(bool AdjustLowWater)(ref void* ptr) {
		auto c = current;
		ptr = *_head;

		// We do not need to adjust the low water mark.
		// Assuming the low water mark is a valid value, checking against it
		// also ensures the bin is not empty.
		if (likely(c != _low_water)) {
			_head++;
			return true;
		}

		// The bin is either empty, so we cannot allocate from it,
		// or we decided to not adjust the low water mark, and we bail.
		if (!AdjustLowWater || unlikely(c == _top)) {
			return false;
		}

		// The bin isn't empty, but the low water mark needs to be adjusted.
		_head++;
		_low_water += PointerSize;
		return true;
	}

	void checkIsEarlier(ushort earlier, ushort later) const {
		if (unlikely(earlier > later)) {
			// This is only possible in case the bin's storage's addresses
			// causes an overflow over 16-bits.
			assert(_top < _bottom);
		}
	}

	ushort delta(ushort a, ushort b) const {
		checkIsEarlier(a, b);
		return (b - a) & ushort.max;
	}

	void** adjustHigher(ushort bits) const {
		auto ptr = cast(void*) _head;
		ptr += delta(current, bits);
		return cast(void**) ptr;
	}

	void** adjustLower(ushort bits) const {
		auto ptr = cast(void*) _head;
		ptr -= delta(bits, current);
		return cast(void**) ptr;
	}
}

struct ThreadBinState {
	bool refilled;
}

bool isValidThreadBinCapacity(uint capacity) {
	if (capacity % 2) {
		return false;
	}

	return MinCapacity <= capacity && capacity <= MaxCapacity;
}

uint computeThreadBinCapacity(uint sizeClass) {
	assert(isSmallSizeClass(sizeClass), "Expected a small size class!");

	import d.gc.slab;
	auto nslots = binInfos[sizeClass].nslots;
	auto capacity = nslots * SlotsMultiplier;

	// Ensure the capacity is even.
	// This simplifies the code in various places because we can
	// split the bin in 2 without special casing for rounding.
	capacity += (capacity % 2);

	// Clamp the capacity to ensure sensible bin size in practice.
	assert(MinCapacity <= MaxCapacity, "Inconsistent ThreadBin spec!");
	assert(isValidThreadBinCapacity(MinCapacity), "Invalid minimum capacity!");
	assert(isValidThreadBinCapacity(MaxCapacity), "Invalid maximum capacity!");

	import d.gc.util;
	capacity = max(capacity, MinCapacity);
	capacity = min(capacity, MaxCapacity);

	assert(isValidThreadBinCapacity(capacity), "Invalid computed capacity!");
	return capacity;
}

enum ThreadCacheSize = computeThreadCacheSize();

uint computeThreadCacheSize() {
	// We peek past the end of the bin when it is empty, so ensure
	// we have one extra pointer in there to do so.
	uint size = 1;

	foreach (s; 0 .. BinCount) {
		size += 2 * computeThreadBinCapacity(s);
	}

	return size;
}

unittest allocate {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	auto ptr = cast(void**) base.reserveAddressSpace(BlockSize);

	foreach (i; 0 .. 200) {
		ptr[i] = cast(void*) 0x100 + i;
	}

	auto tbin = ThreadBin(ptr[0 .. 200]);
	tbin._head -= 100;
	tbin._low_water -= 50 * PointerSize;
	tbin._available += 50 * PointerSize;

	assert(tbin._head is ptr + 100);
	assert(tbin._top == 200 * PointerSize);
	assert(tbin._low_water == 150 * PointerSize);
	assert(tbin._available == 50 * PointerSize);
	assert(tbin._bottom == 0);

	void* p;
	foreach (i; 0 .. 50) {
		assert(!tbin.empty);
		assert(tbin.allocateEasy(p));

		auto v = cast(size_t) p;
		assert(v == 0x164 + i);
	}

	// Now we reached the low water mark.
	foreach (i; 0 .. 50) {
		assert(!tbin.empty);
		assert(!tbin.allocateEasy(p));
		assert(tbin.allocate(p));

		auto v = cast(size_t) p;
		assert(v == 0x196 + i);
	}

	// Now the bin is empty, it all fail.
	assert(tbin.empty);
	assert(!tbin.allocateEasy(p));
	assert(!tbin.allocate(p));
}

unittest addresses {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	static getTBin(void** ptr) {
		auto tbin = ThreadBin(ptr[0 .. 200]);

		tbin._head -= 100;
		tbin._low_water -= 50 * PointerSize;
		tbin._available += 50 * PointerSize;

		assert(tbin._head is ptr + 100);
		return tbin;
	}

	// No wrap around!
	auto ptr0 = cast(void**) base.reserveAddressSpace(BlockSize);
	auto tbin = getTBin(ptr0);

	assert(tbin._top > tbin._bottom);
	assert(!tbin.empty);
	assert(!tbin.full);

	assert(tbin.current == 100 * PointerSize);
	assert(tbin.top is ptr0 + 200);
	assert(tbin.lowWater is ptr0 + 150);
	assert(tbin.available is ptr0 + 50);
	assert(tbin.bottom is ptr0);

	tbin._head = ptr0 + 200;
	assert(tbin.empty);
	assert(!tbin.full);

	tbin._head = ptr0 + 50;
	assert(!tbin.empty);
	assert(tbin.full);

	// Wrap around, head on top!
	enum Offset = 8192 - 100;
	auto ptr1 = ptr0 + Offset;

	tbin = getTBin(ptr1);

	assert(tbin._top < tbin._bottom);
	assert(!tbin.empty);
	assert(!tbin.full);

	assert(tbin.current == 0);
	assert(tbin.top is ptr1 + 200);
	assert(tbin.lowWater is ptr1 + 150);
	assert(tbin.available is ptr1 + 50);
	assert(tbin.bottom is ptr1);

	tbin._head = ptr1 + 200;
	assert(tbin.empty);
	assert(!tbin.full);

	tbin._head = ptr1 + 50;
	assert(!tbin.empty);
	assert(tbin.full);

	// Wrap around, head on the bottom!
	auto ptr2 = ptr1 - 1;
	tbin = getTBin(ptr2);

	assert(tbin._top < tbin._bottom);
	assert(!tbin.empty);
	assert(!tbin.full);

	assert(short(tbin.current) == -PointerSize);
	assert(tbin.top is ptr2 + 200);
	assert(tbin.lowWater is ptr2 + 150);
	assert(tbin.available is ptr2 + 50);
	assert(tbin.bottom is ptr2);

	tbin._head = ptr2 + 200;
	assert(tbin.empty);
	assert(!tbin.full);

	tbin._head = ptr2 + 50;
	assert(!tbin.empty);
	assert(tbin.full);
}
