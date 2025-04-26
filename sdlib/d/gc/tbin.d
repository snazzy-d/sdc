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
 * and store them in the cache. This way, a thread can do multiple
 * allocations before requiring a new round trip in the arena. Even
 * better, if the thread frees its slots, they are returned to the
 * cache and can be reused.
 * 
 * The cache is a buffer containing pointers organized as follow:
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
 * remained in the cache across runs and ensures they eventually get
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
		auto nfill = state.getFill(nmax);
		assert(nfill > 0);

		/**
		 * TODO: We should pass available in addition to nfill to batchAllocSmall.
		 *       This would ensure batchAllocSmall has some wiggle room to provide
		 *       as many slots as possible without allocating new slabs.
		 */
		auto insert = _head - nfill;
		assert(available <= insert);

		auto filled =
			arena.batchAllocSmall(emap, sizeClass, _head, insert, slotSize);
		state.refilled = true;

		/**
		 * Note: If we are worried about security, we might want to shuffle
		 *       our allocations around. This makes the uses of techniques
		 *       like Heap Feng Shui difficult.
		 *       We do not think it is worth the complication and performance
		 *       hit in the general case, but something we might want to add
		 *       in the future for security sensitive applications.
		 * 
		 * http://www.phreedom.org/research/heap-feng-shui/heap-feng-shui.html
		 */

		// The whole space was filled. We are done.
		if (likely(filled is _head)) {
			_head = insert;
			return;
		}

		/**
		 * We could simplify this code by inserting from top to bottom,
		 * in order to avoid moving all the elements when the stack has not
		 * been filled.
		 * 
		 * However, because we allocate from the best slab to the worse one,
		 * this would result in a stack that allocate from the worse slab
		 * before the best ones.
		 * 
		 * So we allocate from the bottom to the top, and move the whole stack
		 * if we did not quite reach the top.
		 */
		while (filled > insert) {
			*(--_head) = *(--filled);
		}

		assert(insert <= _head);
	}

	bool free(void* ptr) {
		if (unlikely(full)) {
			return false;
		}

		*(--_head) = ptr;
		return true;
	}

	void flushToFree(ref CachedExtentMap emap, ref ThreadBinState state) {
		/**
		 * When we use free explicitly, we want to make sure we have room
		 * left in the bin to accommodate further freed elements, even in case
		 * where we refill.
		 */
		state.onFlush();

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
	}

	void fullFlush(ref CachedExtentMap emap) {
		flush(emap, 0);
	}

	void flush(ref CachedExtentMap emap, uint nretain) {
		if (nretain >= ncached) {
			return;
		}

		// We precompute all we need so we can work out of local variables.
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

	void recycle(ref CachedExtentMap emap, ref ThreadBinState state,
	             ubyte sizeClass) {
		auto lw = nlowWater;
		scope(success) _low_water = current;

		if (lw == 0) {
			state.onLowWater();
			return;
		}

		// We aim to flush 3/4 of the items bellow the low water mark.
		auto nflush = lw - (lw >> 2);
		if (nflush < state.recycleDelay) {
			state.recycleDelay -= nflush;
			return;
		}

		// FIXME: Compute recycleDelay properly.
		state.recycleDelay = 0;
		flush(emap, ncached - nflush);

		// We allocated too much since the last recycling, so we reduce
		// the amount by which we refill for next time.
		state.onExtraFill(nmax);
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
	bool flushed;
	ubyte fillShift;
	ubyte recycleDelay;

	uint getFill(ushort nmax) const {
		return nmax >> fillShift;
	}

	bool onFlush() {
		if (flushed) {
			return false;
		}

		flushed = true;
		if (fillShift == 0) {
			fillShift++;
		}

		return true;
	}

	bool onLowWater() {
		// We do not have high demand, do nothing.
		if (!refilled) {
			return false;
		}

		// We have high demand, so we increase how much we fill,
		// while making sure we have room left to free.
		if (fillShift > flushed) {
			fillShift--;
		}

		refilled = false;
		flushed = false;
		return true;
	}

	bool onExtraFill(ushort nmax) {
		// Make sure we do not reduce fill as to never refill.
		if ((nmax >> fillShift) <= 1) {
			return false;
		}

		fillShift++;
		return true;
	}
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

unittest refill {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.filler.base;
	scope(exit) base.clear();

	import d.gc.emap;
	static shared ExtentMap emapStorage;
	auto emap = CachedExtentMap(&emapStorage, base);

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.filler.regionAllocator = &regionAllocator;

	enum BinSize = 200;

	for (ubyte shift = 0; (BinSize >> shift) > 0; shift++) {
		// Setup the bin.
		void*[BinSize] buffer;
		auto tbin = ThreadBin(buffer[0 .. BinSize]);
		assert(tbin.empty);

		// Setup the state.
		ThreadBinState state;
		state.fillShift = shift;

		import d.gc.slab;
		enum SizeClass = 0;
		auto slotSize = binInfos[SizeClass].slotSize;

		// Refill without shift will refill the whole bin.
		tbin.refill(emap, &arena, state, SizeClass, slotSize);

		assert(state.refilled, "Thread bin not refilled!");
		assert(tbin.ncached == BinSize >> shift,
		       "Invalid cached element count!");
	}
}

unittest ThreadBinState {
	enum BinSize = 200;

	// Setup the state.
	ThreadBinState state;
	assert(!state.refilled, "Thread bin refilled!");
	assert(!state.flushed, "Thread bin flushed!");
	assert(state.getFill(BinSize) == BinSize, "Unexpected fill!");

	// When we flush, we reduce the max fill.
	state.onFlush();

	assert(!state.refilled, "Thread bin refilled!");
	assert(state.flushed, "Thread bin not flushed!");
	assert(state.getFill(BinSize) == BinSize / 2, "Unexpected fill!");

	// On repeat, nothing happens.
	state.onFlush();

	assert(!state.refilled, "Thread bin refilled!");
	assert(state.flushed, "Thread bin not flushed!");
	assert(state.getFill(BinSize) == BinSize / 2, "Unexpected fill!");

	// When flushed is cleared, we redo, but never
	// reduce fill to less than half the bin.
	state.flushed = false;
	state.onFlush();

	assert(!state.refilled, "Thread bin refilled!");
	assert(state.flushed, "Thread bin not flushed!");
	assert(state.getFill(BinSize) == BinSize / 2, "Unexpected fill!");

	// On low water, we do nothing if we haven't refilled.
	state.onLowWater();

	assert(!state.refilled, "Thread bin refilled!");
	assert(state.flushed, "Thread bin not flushed!");
	assert(state.getFill(BinSize) == BinSize / 2, "Unexpected fill!");

	// If we refilled, but also flushed, we clear the flags,
	// but don't increase the size past BinSize / 2.
	state.refilled = true;
	state.flushed = true;
	state.onLowWater();

	assert(!state.refilled, "Thread bin refilled!");
	assert(!state.flushed, "Thread bin flushed!");
	assert(state.getFill(BinSize) == BinSize / 2, "Unexpected fill!");

	// If we refilled but not flushed, we can go to the max.
	state.refilled = true;
	state.onLowWater();

	assert(!state.refilled, "Thread bin refilled!");
	assert(!state.flushed, "Thread bin flushed!");
	assert(state.getFill(BinSize) == BinSize, "Unexpected fill!");

	// If we filled too much, we reduce the fill.
	foreach (s; 1 .. 7) {
		state.onExtraFill(BinSize);

		assert(!state.refilled, "Thread bin refilled!");
		assert(!state.flushed, "Thread bin flushed!");
		assert(state.getFill(BinSize) == BinSize >> s, "Unexpected fill!");
	}

	// But we always fill at least 1 element!
	foreach (s; 0 .. 2) {
		state.onExtraFill(BinSize);

		assert(!state.refilled, "Thread bin refilled!");
		assert(!state.flushed, "Thread bin flushed!");
		assert(state.getFill(BinSize) == 1, "Unexpected fill!");
	}

	// If we refilled, but also flushed, the increase in fill is capped.
	foreach (s; 0 .. 6) {
		state.refilled = true;
		state.flushed = true;
		state.onLowWater();

		assert(!state.refilled, "Thread bin refilled!");
		assert(!state.flushed, "Thread bin flushed!");
		assert(state.getFill(BinSize) == BinSize >> (6 - s),
		       "Unexpected fill!");
	}

	foreach (s; 0 .. 2) {
		state.refilled = true;
		state.flushed = true;
		state.onLowWater();

		assert(!state.refilled, "Thread bin refilled!");
		assert(!state.flushed, "Thread bin flushed!");
		assert(state.getFill(BinSize) == BinSize / 2, "Unexpected fill!");
	}
}

unittest recycle {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.filler.base;
	scope(exit) base.clear();

	import d.gc.emap;
	static shared ExtentMap emapStorage;
	auto emap = CachedExtentMap(&emapStorage, base);

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.filler.regionAllocator = &regionAllocator;

	enum BinSize = 200;
	enum SizeClass = 0;

	import d.gc.slab;
	auto slotSize = binInfos[SizeClass].slotSize;

	// Setup the bin.
	void*[BinSize] buffer;
	auto tbin = ThreadBin(buffer[0 .. BinSize]);
	assert(tbin.empty);

	// Refill the bin, check it is in the expected state.
	ThreadBinState state;
	tbin.refill(emap, &arena, state, SizeClass, slotSize);

	assert(state.refilled, "Thread bin not refilled!");
	assert(state.getFill(tbin.nmax) == BinSize, "Unexpected fill!");
	assert(tbin.ncached == BinSize, "Invalid cached element count!");
	assert(tbin.nlowWater == 0, "Invalid low water mark!");

	// Recycling a bin that is full with a low water mark of zero will
	// raise the low water mark and reset the refilled flag.
	tbin.recycle(emap, state, SizeClass);

	assert(!state.refilled, "Thread bin refilled!");
	assert(state.getFill(tbin.nmax) == BinSize, "Unexpected fill!");
	assert(tbin.ncached == BinSize, "Invalid cached element count!");
	assert(tbin.nlowWater == BinSize, "Invalid low water mark!");

	// FIXME: We have a non zero low water mark, we should flush,
	//        but there is no sensible way to do this at the moment.

	// Allocating from a bin that is in high demand increase the refill capacity.
	state.fillShift = 3;
	for (uint s = 3; s > 0; s--) {
		state.refilled = true;
		tbin._low_water = tbin._top;

		assert(state.refilled, "Thread bin not refilled!");
		assert(state.getFill(tbin.nmax) == BinSize >> s, "Unexpected fill!");
		assert(tbin.ncached == BinSize, "Invalid cached element count!");
		assert(tbin.nlowWater == 0, "Invalid low water mark!");

		tbin.recycle(emap, state, SizeClass);

		assert(!state.refilled, "Thread bin refilled!");
		assert(state.getFill(tbin.nmax) == BinSize >> (s - 1),
		       "Unexpected fill!");
		assert(tbin.ncached == BinSize, "Invalid cached element count!");
		assert(tbin.nlowWater == BinSize, "Invalid low water mark!");
	}

	// If we have flushed, do not increase the size past BinSize / 2.
	state.fillShift = 3;
	for (uint s = 3; s > 0; s--) {
		state.refilled = true;
		state.flushed = true;
		tbin._low_water = tbin._top;

		assert(state.refilled, "Thread bin not refilled!");
		assert(state.flushed, "Thread bin not flushed!");
		assert(state.getFill(tbin.nmax) == BinSize >> s, "Unexpected fill!");
		assert(tbin.ncached == BinSize, "Invalid cached element count!");
		assert(tbin.nlowWater == 0, "Invalid low water mark!");

		tbin.recycle(emap, state, SizeClass);

		auto ps = s > 1 ? s - 1 : 1;
		assert(!state.refilled, "Thread bin refilled!");
		assert(!state.flushed, "Thread bin flushed!");
		assert(state.getFill(tbin.nmax) == BinSize >> ps, "Unexpected fill!");
		assert(tbin.ncached == BinSize, "Invalid cached element count!");
		assert(tbin.nlowWater == BinSize, "Invalid low water mark!");
	}
}
