module d.gc.mtqueue;

import d.sync.atomic;

import d.gc.util;
import d.gc.spec;

struct ConcurentQueue(T) {
private:
	// XXX: Not strictly necessary but this makes the math in there simpler.
	static assert(T.sizeof == PointerSize, "Expected pointer sized elements!");

	/**
	 * In order to avoid false sharing, we make sure each of the control
	 * elements of the ring buffer are on their own cache line.
	 */
	T[] _buffer;
	Padding!2 _pad0;

	@property
	T[] buffer() shared {
		// It is not necessary to access the buffer in an atomic fashion,
		// so we bypass shared for it.
		return (cast(ConcurentQueue*) &this)._buffer;
	}

	/**
	 * The ring buffer has the following structure:
	 * ... empty --|-- reading --|-- queued --|-- writing --|-- empty ...
	 *             ^             ^            ^             ^
	 *             tail          clearing     head          reserved
	 * 
	 * The `empty` area simply contains empty slots with no relevant data.
	 * 
	 * The `reading` area contains item that are currently being read.
	 * Because read operation may not be atomic, the reader first reserve
	 * a certain number of slot for itself by bumping the `clearing` pointer,
	 * then bumps `tail` when it is done reading.
	 * 
	 * The `queued` area contains element that have been stored in the queue
	 * and are waiting for their turn to be read.
	 * 
	 * Finally, the `writing` area contains element that are currently being
	 * written. Just like read, writes may not be atomic, so the writer
	 * reserve a number of slot for itself by bumping the `reserved` pointer,
	 * than bumps the `head` pointer when it is done.
	 */
	Atomic!size_t tail;
	Padding!1 _pad1;

	Atomic!size_t clearing;
	Padding!1 _pad2;

	Atomic!size_t head;
	Padding!1 _pad3;

	Atomic!size_t reserved;
	Padding!1 _pad4;

public:
	this(T[] buffer) {
		assert(isAligned(buffer.ptr, CacheLine),
		       "The buffer must be cache line aligned.");
		assert(isPow2(buffer.length), "The buffer size must be a power of 2!");
		assert(buffer.length >= PointerInCacheLine,
		       "The buffer must be larger than a cache line!");

		_buffer = buffer;
	}

	void insert(T[] elements, ref Overflow!T overflow) shared {
		overflow.flush(this);

		auto count = batchInsert(elements);
		elements = elements[count .. elements.length];

		if (elements.length > 0) {
			// We have extra elements, they go in the overflow.
			overflow.insert(elements);
		}
	}

	size_t pop(T[] elements, ref Overflow!T overflow) shared {
		// Try to fill in from the overflow.
		auto count = overflow.pop(elements);
		if (count > 0) {
			// We had something in the overflow, let's avoid  popping from the
			// queue to avoid contention, but try to flush to avoid starving.
			overflow.flush(this);
			return count;
		}

		assert(overflow.empty, "Overflow was not used to fill!");
		return batchPop(elements);
	}

private:
	size_t batchInsertStep(T[] elements) shared {
		assert(elements.length > 0, "Empty buffer!");

		auto slice = buffer;
		auto size = slice.length;
		auto mask = size - 1;

		auto r = reserved.load();
		size_t count;

		while (true) {
			// Make sure we touch at most 2 cache lines.
			auto m =
				2 * PointerInCacheLine - alignDownOffset(r, PointerInCacheLine);
			count = min(elements.length, m);

			auto t = tail.load();

			// Make sure we do not try to write more than we have free slots.
			count = min(count, t + size - r);

			// We have nothing to insert, we are done.
			if (count == 0) {
				return 0;
			}

			// Try to reserve the number of slots we want.
			if (reserved.casWeak(r, r + count)) {
				break;
			}
		}

		// Write the elements in the slots we just reserved.
		foreach (i; 0 .. count) {
			auto n = (r + i) & mask;
			slice[n] = elements[i];
		}

		// Now update the head and exit.
		while (true) {
			auto h = r;
			if (head.cas(h, h + count)) {
				return count;
			}

			assert(h <= r, "Head passed the reserved area!");
		}
	}

	size_t batchInsert(T[] elements) shared {
		size_t count = 0;

		while (elements.length > 0) {
			auto inserted = batchInsertStep(elements);
			if (inserted == 0) {
				break;
			}

			elements = elements[inserted .. elements.length];
			count += inserted;
		}

		return count;
	}

	size_t batchPopStep(T[] elements) shared {
		assert(elements.length > 0, "Empty buffer!");

		auto slice = buffer;
		auto size = slice.length;
		auto mask = size - 1;

		auto c = clearing.load();
		size_t count;

		while (true) {
			// Make sure we touch at most 2 cache lines.
			auto m =
				2 * PointerInCacheLine - alignDownOffset(c, PointerInCacheLine);
			count = min(elements.length, m);

			auto h = head.load();

			// Make sure we do not try to read more than we have filled slots.
			count = min(count, h - c);

			// We have nothing to pop, we are done.
			if (count == 0) {
				return 0;
			}

			// Try to clear the number of slots we want.
			if (clearing.casWeak(c, c + count)) {
				break;
			}
		}

		// Read the elements in the slots we are clearing.
		foreach (i; 0 .. count) {
			auto n = (c + i) & mask;
			elements[i] = slice[n];
		}

		// Now update the tail and exit.
		while (true) {
			auto t = c;
			if (tail.cas(t, t + count)) {
				return count;
			}

			assert(t <= c, "Tail passed the clearing area!");
		}
	}

	size_t batchPop(T[] elements) shared {
		size_t count = 0;

		while (elements.length > 0) {
			auto popped = batchPopStep(elements);
			if (popped == 0) {
				break;
			}

			elements = elements[popped .. elements.length];
			count += popped;
		}

		return count;
	}
}

unittest mtqueue {
	// Create a ConcurentQueue to test flush.
	size_t[32 + PointerInCacheLine] qbufStorage;
	auto qbufAligned = alignUp(qbufStorage.ptr, CacheLine);
	auto qbuf = (cast(size_t*) qbufAligned)[0 .. 32];
	auto queue = shared(ConcurentQueue!size_t)(qbuf);

	Overflow!size_t o;

	void checkMetadata(size_t tail, size_t head) {
		assert(queue.tail.load() == tail);
		assert(queue.clearing.load() == tail);

		assert(queue.head.load() == head);
		assert(queue.reserved.load() == head);
	}

	void check(size_t[] values, size_t[] overflow, size_t tail, size_t head) {
		checkMetadata(tail, head);

		assert(values.length == head - tail);
		foreach (i, v; values) {
			assert(queue.buffer[(tail + i) % 32] == v);
		}

		assert(o.slice.length == overflow.length);
		foreach (i, v; o.slice) {
			assert(overflow[i] == v);
		}
	}

	size_t[] i32 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
	                17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31];

	// Fill the queue.
	queue.insert(i32, o);
	check(i32, [], 0, 32);

	// If we try to insert more, it goes in the overflow.
	queue.insert(i32, o);
	check(i32, i32, 0, 32);

	// We pop from the overflow first.
	size_t[32] eBuf;
	auto elements = eBuf[0 .. eBuf.length];

	assert(queue.pop(elements[0 .. 16], o) == 16);
	check(i32, i32[0 .. 16], 0, 32);

	// If we popped something from the overflow, we don't pop from the queue.
	assert(queue.pop(elements, o) == 16);
	check(i32, [], 0, 32);

	// If we pop some more, we pop from the queue.
	assert(queue.pop(elements[0 .. 16], o) == 16);
	check(i32[16 .. 32], [], 16, 32);

	// If we insert more, we insert what's in the overflow first, the the rest.
	size_t[] j32 =
		[32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
		 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63];

	o.insert(j32[0 .. 16]);
	check(i32[16 .. 32], j32[0 .. 16], 16, 32);

	queue.insert(j32[16 .. 32], o);
	check(i32[16 .. 32] ~ j32[0 .. 16], j32[16 .. 32], 16, 48);

	// If we pop from the overflow, but there is more, it gets queued.
	assert(queue.pop(elements, o) == 16);
	assert(queue.pop(elements[0 .. 16], o) == 16);
	check(j32[0 .. 16], [], 32, 48);

	o.insert(i32);
	check(j32[0 .. 16], i32, 32, 48);

	assert(queue.pop(elements[0 .. 16], o) == 16);
	check(j32[0 .. 16] ~ i32[0 .. 16], [], 32, 64);

	// Check that we can pop from an empty queue.
	assert(queue.pop(elements, o) == 32);
	check([], [], 64, 64);

	assert(queue.pop(elements, o) == 0);
	check([], [], 64, 64);
}

struct Overflow(T) {
private:
	T[] buffer;

	size_t tail;
	size_t head;

public:
	@property
	size_t length() {
		return head - tail;
	}

	@property
	bool empty() {
		return length == 0;
	}

	@property
	size_t capacity() {
		return buffer.length - head;
	}

	@property
	T* tailPtr() {
		return buffer.ptr + tail;
	}

	@property
	T* headPtr() {
		return buffer.ptr + head;
	}

	@property
	T[] slice() {
		return tailPtr[0 .. length];
	}

	void insert(T[] elements) {
		auto count = elements.length;
		reserve(count);

		memmove(headPtr, elements.ptr, count * T.sizeof);
		head += count;
	}

	size_t pop(T[] elements) {
		auto count = min(length, elements.length);
		if (count == 0) {
			return 0;
		}

		head -= count;
		memmove(elements.ptr, headPtr, count * T.sizeof);

		if (head == tail) {
			head = 0;
			tail = 0;
		}

		return count;
	}

	void flush(ref shared ConcurentQueue!T queue) {
		tail += queue.batchInsert(slice);
		if (head == tail) {
			head = 0;
			tail = 0;
		}
	}

	void clear() {
		import d.gc.tcache;
		threadCache.free(buffer.ptr);

		buffer = [];
		head = 0;
		tail = 0;
	}

private:
	void reserve(size_t count) {
		if (capacity >= count) {
			// We have the capacity, do nothing.
			return;
		}

		slide();

		// Make sure we do not continuously slide when we are tight.
		auto slack = buffer.length / 4;
		if (capacity >= count && capacity >= slack) {
			return;
		}

		// We want to make sure we grow AND that we have enough
		// space for `count` elements.
		auto slots = max(length + count, buffer.length + 1);

		// This ensures we only use large allocations.
		enum MinBufferSize = 4 * PageSize;

		auto size = slots * T.sizeof;
		if (size < MinBufferSize) {
			size = MinBufferSize;
		} else {
			import d.gc.sizeclass;
			size = getAllocSize(size);
		}

		import d.gc.tcache;
		auto ptr = threadCache.realloc(buffer.ptr, size, false);
		buffer = (cast(T*) ptr)[0 .. size / T.sizeof];
	}

	void slide() {
		if (tail == 0) {
			return;
		}

		auto count = tail;
		if (count > 0) {
			memmove(buffer.ptr, tailPtr, count * T.sizeof);
		}

		head -= count;
		tail = 0;
	}
}

unittest overflow {
	Overflow!size_t o;

	void checkMetadata(size_t bufferLength, size_t tail, size_t head) {
		assert(o.buffer.length == bufferLength);
		assert(o.tail == tail);
		assert(o.head == head);

		assert(o.length == head - tail);
		assert(o.empty == (head == tail));

		assert(o.capacity == bufferLength - head);
	}

	void check(size_t[] values, size_t bufferLength, size_t tail, size_t head) {
		assert(bufferLength >= values.length);
		assert(values.length == head - tail);

		checkMetadata(bufferLength, tail, head);

		foreach (i, e; o.slice) {
			assert(e == values[i]);
		}
	}

	// Insert some elements.
	o.insert([1, 2, 3, 4]);
	check([1, 2, 3, 4], 2048, 0, 4);

	// Pop one element.
	size_t[16] eBuf;
	auto elements = eBuf[0 .. eBuf.length];

	assert(o.pop(elements[0 .. 1]) == 1);
	check([1, 2, 3], 2048, 0, 3);

	assert(elements[0] == 4);

	// Insert elements in a non empty Overflow.
	o.insert([5, 6, 7, 8]);
	check([1, 2, 3, 5, 6, 7, 8], 2048, 0, 7);

	// Pop multiple elements.
	assert(o.pop(elements[0 .. 3]) == 3);
	check([1, 2, 3, 5], 2048, 0, 4);

	assert(elements[0] == 6);
	assert(elements[1] == 7);
	assert(elements[2] == 8);

	// Try to pop more elements than there is in the Overflow.
	assert(o.pop(elements[0 .. 8]) == 4);
	check([], 2048, 0, 0);

	assert(elements[0] == 1);
	assert(elements[1] == 2);
	assert(elements[2] == 3);
	assert(elements[3] == 5);

	// Insert more element and try to pop that exact number.
	size_t[] i16 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];

	o.insert(i16);
	check(i16, 2048, 0, 16);

	assert(o.pop(elements) == 16);
	check([], 2048, 0, 0);

	foreach (i; 0 .. 16) {
		assert(elements[i] == i);
	}

	// Create a ConcurentQueue to test flush.
	size_t[8 + PointerInCacheLine] qbufStorage;
	auto qbufAligned = alignUp(qbufStorage.ptr, CacheLine);
	auto qbuf = (cast(size_t*) qbufAligned)[0 .. 8];
	auto queue = shared(ConcurentQueue!size_t)(qbuf);

	o.insert(i16);
	check(i16, 2048, 0, 16);

	// Flush one cache line worth of elements.
	o.flush(queue);
	check(i16[8 .. 16], 2048, 8, 16);

	// When popping from the queue, if there is something in the overflow,
	// we use that first.
	assert(queue.pop(elements[0 .. 4], o) == 4);
	check(i16[8 .. 12], 2048, 8, 12);

	assert(elements[0] == 12);
	assert(elements[1] == 13);
	assert(elements[2] == 14);
	assert(elements[3] == 15);

	// When we run out of elements in the overflow, but avoid the queue.
	assert(queue.pop(elements, o) == 4);

	// Note that the head and tail reset to 0 when the overflow is empty.
	check([], 2048, 0, 0);

	assert(elements[0] == 8);
	assert(elements[1] == 9);
	assert(elements[2] == 10);
	assert(elements[3] == 11);

	// Now that the overflow is empty, we pop from the queue.
	assert(queue.pop(elements, o) == 8);

	foreach (i; 0 .. 8) {
		assert(elements[i] == i);
	}

	// Check that head and tail also reset on flush.
	o.insert(i16[0 .. 8]);
	check(i16[0 .. 8], 2048, 0, 8);

	o.flush(queue);
	check([], 2048, 0, 0);

	// If we keep inserting, eventually, we'll resize.
	foreach (i; 0 .. 128) {
		o.insert(i16);
		checkMetadata(2048, 0, 16 * (i + 1));
	}

	checkMetadata(2048, 0, 2048);

	// The overflow is full, let's flush some of it.
	foreach (i; 0 .. 64) {
		Overflow!size_t oDummy;
		assert(queue.pop(elements, oDummy) == 8);

		o.flush(queue);
		checkMetadata(2048, 8 * (i + 1), 2048);
	}

	checkMetadata(2048, 512, 2048);

	// If we try to add more, we need to slide the elements.
	o.insert(i16);
	checkMetadata(2048, 0, 1552);

	// Fill back in.
	foreach (i; 0 .. 31) {
		o.insert(i16);
		checkMetadata(2048, 0, 1568 + 16 * i);
	}

	checkMetadata(2048, 0, 2048);

	// This time, leave slightly less slack, so we reallocate.
	foreach (i; 0 .. 63) {
		Overflow!size_t oDummy;
		assert(queue.pop(elements, oDummy) == 8);

		o.flush(queue);
		checkMetadata(2048, 8 * (i + 1), 2048);
	}

	checkMetadata(2048, 504, 2048);

	Overflow!size_t oDummy;
	assert(queue.pop(elements[0 .. 7], oDummy) == 7);

	o.flush(queue);
	checkMetadata(2048, 511, 2048);

	// Now we have one more element in the overflow, we will resize.
	o.insert(i16[0 .. 1]);
	checkMetadata(2560, 0, 1538);

	// Clear the overflow.
	o.clear();
	check([], 0, 0, 0);
	assert(o.buffer.ptr is null);
}
