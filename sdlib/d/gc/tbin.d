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

		auto insert = _head - nfill;
		assert(available <= insert);

		auto requested = insert + (nfill >> 1) + 1;
		assert(insert < requested && requested <= _head);

		auto filled = arena.batchAllocSmall(emap, sizeClass, _head, insert,
		                                    requested, slotSize);
		state.onRefill();

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

	bool flush(ref CachedExtentMap emap, uint nretain) {
		if (nretain >= ncached) {
			return false;
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

		return true;
	}

	bool recycle(ref CachedExtentMap emap, ref ThreadBinState state,
	             ubyte sizeClass) {
		auto lw = nlowWater;
		scope(success) _low_water = current;

		if (lw == 0) {
			state.onLowWater();
			return false;
		}

		// We allocated too much since the last recycling, so we reduce
		// the amount by which we refill for next time.
		state.onRecycle(nmax);

		// We aim to flush 3/4 of the items bellow the low water mark.
		auto nflush = lw - (lw >> 2);
		return flush(emap, ncached - nflush);
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
	/**
	 * The base/offset pair is used to determine how much elements
	 * we should refill when the bin is empty.
	 *
	 * Refilling too much causes the bin to retain a ton of unused memory,
	 * and unnecessary flushes in case the user wants to free. Not refilling
	 * enough will cause unnecessary refills.
	 * 
	 * We track the "base" demand in the `base` field. This tracks how much
	 * long term demand there is for elements in that bin. This is updated
	 * every time the bin is recycled, based on what happened since the last
	 * recycle event.
	 * 
	 * Recycle event don't happened regularly, and we want to make sure we
	 * don't choke the program in case there is a sudden burst in demand
	 * for a certain size class. To avoid this, we increase the `offset`
	 * after every refill. As soon as it looks like we might be allocating
	 * too much, `offset` is reset to 0. This happens when we need to flush
	 * and when we notice low demand when recycling the bin.
	 */
	ubyte base;
	ubyte offset;

	bool refilled;
	bool flushed;

	uint getFill(ushort nmax) const {
		assert(base >= offset, "Corrupted base/offset pair!");
		return nmax >> (base - offset);
	}

	void onRefill() {
		refilled = true;
		if (offset < base) {
			offset++;
		}
	}

	void onFlush() {
		// If we need to flush, the burst in demand is over.
		offset = 0;

		// Make sure we'll have room to free after the next refill.
		// This ensures we don't refill/flush full bins.
		if (!flushed && base == 0) {
			base++;
		}

		flushed = true;
	}

	void onLowWater() {
		// We do not have high demand, do nothing.
		if (!refilled) {
			return;
		}

		// We have high demand, so we increase how much we fill,
		// while making sure we have room left to free.
		if (base > flushed) {
			base--;
		}

		// Make sure we maintain offset invariant.
		if (offset > base) {
			offset--;
		}

		refilled = false;
		flushed = false;
	}

	void onRecycle(ushort nmax) {
		// It does look like the burst in demand is over.
		offset = 0;

		// Make sure we do not reduce fill as to never refill.
		if ((nmax >> base) > 1) {
			base++;
		}
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
		state.base = shift;

		import d.gc.slab;
		enum SizeClass = 0;
		auto slotSize = binInfos[SizeClass].slotSize;

		// Refill without shift will refill the whole bin.
		tbin.refill(emap, &arena, state, SizeClass, slotSize);

		assert(state.refilled, "Thread bin not refilled!");
		assert(state.base == shift, "Invalid thread bin base!");
		assert(state.offset == (shift > 0), "Invalid thread bin offset!");
		assert(tbin.ncached == BinSize >> shift,
		       "Invalid cached element count!");
	}
}

unittest ThreadBinState {
	enum BinSize = 200;

	// Setup the state.
	ThreadBinState state;

	auto checkState(bool refilled, bool flushed, uint nfill) {
		assert(state.refilled == refilled, "Thread bin refilled!");
		assert(state.flushed == flushed, "Thread bin flushed!");
		assert(state.getFill(BinSize) == nfill, "Unexpected fill!");
	}

	checkState(false, false, BinSize);

	// When we flush, we reduce the max fill.
	state.onFlush();
	checkState(false, true, BinSize / 2);

	// On repeat, nothing happens.
	state.onFlush();
	checkState(false, true, BinSize / 2);

	// When flushed is cleared, we redo, but never
	// reduce fill to less than half the bin.
	state.flushed = false;
	state.onFlush();
	checkState(false, true, BinSize / 2);

	// On low water, we do nothing if we haven't refilled.
	state.onLowWater();
	checkState(false, true, BinSize / 2);

	// If we refilled, but also flushed, we clear the flags,
	// but don't increase the size past BinSize / 2.
	state.refilled = true;
	state.flushed = true;
	state.onLowWater();
	checkState(false, false, BinSize / 2);

	// If we refilled but not flushed, we can go to the max.
	state.refilled = true;
	state.onLowWater();
	checkState(false, false, BinSize);

	// If we filled too much, we reduce the fill.
	foreach (s; 1 .. 7) {
		state.onRecycle(BinSize);
		checkState(false, false, BinSize >> s);
	}

	// But we always fill at least 1 element!
	foreach (s; 0 .. 2) {
		state.onRecycle(BinSize);
		checkState(false, false, 1);
	}

	// If we refilled, but also flushed, the increase in fill is capped.
	foreach (s; 0 .. 6) {
		state.refilled = true;
		state.flushed = true;
		state.onLowWater();
		checkState(false, false, BinSize >> (6 - s));
	}

	foreach (s; 0 .. 2) {
		state.refilled = true;
		state.flushed = true;
		state.onLowWater();

		checkState(false, false, BinSize / 2);
	}
}

unittest ThreadBinStateOffset {
	enum BinSize = 200;

	// Setup the state.
	ThreadBinState state;
	state.base = 2;

	auto checkState(bool refilled, bool flushed, ubyte base, ubyte offset,
	                uint nfill) {
		assert(state.refilled == refilled, "Thread bin refilled!");
		assert(state.flushed == flushed, "Thread bin flushed!");
		assert(state.base == base, "Invalid base!");
		assert(state.offset == offset, "Invalid offset!");
		assert(state.getFill(BinSize) == nfill, "Unexpected fill!");
	}

	checkState(false, false, 2, 0, BinSize / 4);

	state.onRefill();
	checkState(true, false, 2, 1, BinSize / 2);

	state.onRefill();
	checkState(true, false, 2, 2, BinSize);

	// When we reached the point where we fill the bin,
	// we stop increasing the offset.
	state.onRefill();
	checkState(true, false, 2, 2, BinSize);

	// When recycling, we reset the offset.
	state.onRecycle(BinSize);
	checkState(true, false, 3, 0, BinSize / 8);

	// When flushing, the offset is reset to zero.
	state.offset = 3;
	checkState(true, false, 3, 3, BinSize);

	state.onFlush();
	checkState(true, true, 3, 0, BinSize / 8);

	// On low water, we decrease the offset if necessary.
	state.offset = 3;
	checkState(true, true, 3, 3, BinSize);

	state.onLowWater();
	checkState(false, false, 2, 2, BinSize);

	// But we do not if it is not necessary.
	state.offset = 1;
	state.refilled = true;
	checkState(true, false, 2, 1, BinSize / 2);

	state.onLowWater();
	checkState(false, false, 1, 1, BinSize);
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

	auto checkState(bool refilled, bool flushed, uint nfill, uint ncached,
	                uint nlowWater) {
		assert(state.refilled == refilled, "Unexpected refilled state!");
		assert(state.flushed == flushed, "Unexpected flushed state!");
		assert(state.getFill(tbin.nmax) == nfill, "Unexpected fill!");
		assert(tbin.ncached == ncached, "Invalid cached element count!");
		assert(tbin.nlowWater == nlowWater, "Invalid low water mark!");
	}

	tbin.refill(emap, &arena, state, SizeClass, slotSize);
	checkState(true, false, BinSize, BinSize, 0);

	// Recycling a bin that is full with a low water mark of zero will
	// raise the low water mark and reset the refilled flag.
	assert(!tbin.recycle(emap, state, SizeClass), "Unexpected flush!");
	checkState(false, false, BinSize, BinSize, BinSize);

	// FIXME: We have a non zero low water mark, we should flush,
	//        but because we aren't using a arena that the code can
	//        find from the extent map, there is no way to actually
	//        test this with the current setup.

	// Allocating from a bin that is in high demand increase the refill capacity.
	state.base = 3;
	for (uint s = 3; s > 0; s--) {
		state.refilled = true;
		tbin._low_water = tbin._top;

		checkState(true, false, BinSize >> s, BinSize, 0);

		assert(!tbin.recycle(emap, state, SizeClass), "Unexpected flush!");
		checkState(false, false, BinSize >> (s - 1), BinSize, BinSize);
	}

	// If we have flushed, do not increase the size past BinSize / 2.
	state.base = 3;
	for (uint s = 3; s > 0; s--) {
		state.refilled = true;
		state.flushed = true;
		tbin._low_water = tbin._top;

		checkState(true, true, BinSize >> s, BinSize, 0);

		assert(!tbin.recycle(emap, state, SizeClass), "Unexpected flush!");

		auto ps = s > 1 ? s - 1 : 1;
		checkState(false, false, BinSize >> ps, BinSize, BinSize);
	}
}
