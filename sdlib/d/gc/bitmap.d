module d.gc.bitmap;

import d.gc.util;

import sdc.intrinsics;

struct Bitmap(uint N) {
private:
	enum uint NimbleSize = 8 * ulong.sizeof;
	enum uint NimbleCount = (N + NimbleSize - 1) / NimbleSize;
	enum uint DeadBits = NimbleSize * NimbleCount - N;

	ulong[NimbleCount] bits;

public:
	void clear() {
		foreach (i; 0 .. NimbleCount) {
			bits[i] = 0;
		}
	}

	bool valueAt(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		auto i = index / NimbleSize;
		auto o = index % NimbleSize;
		auto n = bits[i] >> o;

		return (n & 0x01) != 0;
	}

	uint setFirst() {
		// FIXME: in contract
		assert(countBits(0, N) < N, "Bitmap is full!");

		foreach (i; 0 .. NimbleCount) {
			auto n = bits[i] + 1;
			if (n == 0) {
				continue;
			}

			bits[i] |= n;

			uint ret = i * NimbleSize;
			ret += countTrailingZeros(n);

			return ret;
		}

		return -1;
	}

	uint findSet(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		return findValue!true(index);
	}

	uint findClear(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		return findValue!false(index);
	}

	uint findValue(bool V)(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		auto i = index / NimbleSize;
		auto offset = index % NimbleSize;

		auto flip = ulong(V) - 1;
		auto mask = ulong.max << offset;
		auto current = (bits[i++] ^ flip) & mask;

		while (current == 0) {
			if (i >= NimbleCount) {
				return N;
			}

			current = bits[i++] ^ flip;
		}

		uint ret = countTrailingZeros(current);
		ret += (i - 1) * NimbleSize;
		if (DeadBits > 0) {
			ret = max(ret, N);
		}

		return ret;
	}

	int findSetBackward(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		return findValueBackward!true(index);
	}

	int findClearBackward(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		return findValueBackward!false(index);
	}

	int findValueBackward(bool V)(uint index) const {
		// FIXME: in contracts.
		assert(index < N);

		int i = index / NimbleSize;
		auto offset = index % NimbleSize;

		// XXX: When offset is zero, mask is 0 and
		// we do a round of computation for nothing.
		auto flip = ulong(V) - 1;
		auto mask = (ulong(1) << offset) - 1;
		auto current = (bits[i--] ^ flip) & mask;

		while (current == 0) {
			if (i < 0) {
				return -1;
			}

			current = bits[i--] ^ flip;
		}

		int clz = countLeadingZeros(current);
		return (i + 2) * NimbleSize - clz - 1;
	}

	bool nextFreeRange(uint start, ref uint index, ref uint length) const {
		// FIXME: in contract.
		assert(start < N);

		auto i = findClear(start);
		if (i >= N) {
			return false;
		}

		auto j = findSet(i);
		index = i;
		length = j - i;
		return true;
	}

	void setBit(uint index) {
		setBitValue!true(index);
	}

	void clearBit(uint index) {
		setBitValue!false(index);
	}

	void setBitValue(bool V)(uint index) {
		// FIXME: in contracts.
		assert(index < N);

		auto i = index / NimbleSize;
		auto o = index % NimbleSize;
		auto b = ulong(1) << o;

		if (V) {
			bits[i] |= b;
		} else {
			bits[i] &= ~b;
		}
	}

	void setRange(uint index, uint length) {
		setRangeValue!true(index, length);
	}

	void clearRange(uint index, uint length) {
		setRangeValue!false(index, length);
	}

	void setRangeValue(bool V)(uint index, uint length) {
		// FIXME: in contracts.
		assert(index < N);
		assert(length > 0 && length <= N);
		assert(index + length <= N);

		static setBits(ref ulong n, ulong mask) {
			if (V) {
				n |= mask;
			} else {
				n &= ~mask;
			}
		}

		auto i = index / NimbleSize;
		auto offset = index % NimbleSize;

		if (length <= NimbleSize - offset) {
			// The whole count fit within one nimble.
			auto shift = NimbleSize - length;
			auto mask = (ulong.max >> shift) << offset;
			setBits(bits[i], mask);
			return;
		}

		setBits(bits[i++], ulong.max << offset);

		length += offset;
		length -= NimbleSize;

		while (length > NimbleSize) {
			setBits(bits[i++], ulong.max);
			length -= NimbleSize;
		}

		assert(1 <= length && length <= NimbleSize);
		auto shift = (NimbleSize - length) % NimbleSize;
		setBits(bits[i++], ulong.max >> shift);
	}

	uint countBits(uint index, uint length) const {
		// FIXME: in contracts.
		assert(index < N);
		assert(length <= N);
		assert(index + length <= N);

		if (length == 0) {
			return 0;
		}

		auto i = index / NimbleSize;
		auto offset = index % NimbleSize;

		if (length <= NimbleSize - offset) {
			// The whole count fit within one nimble.
			auto shift = NimbleSize - length;
			auto mask = (ulong.max >> shift) << offset;
			return popCount(bits[i] & mask);
		}

		auto mask = ulong.max << offset;
		uint count = popCount(bits[i++] & mask);

		length += offset;
		length -= NimbleSize;

		while (length > NimbleSize) {
			count += popCount(bits[i++]);
			length -= NimbleSize;
		}

		assert(1 <= length && length <= NimbleSize);
		auto shift = (NimbleSize - length) % NimbleSize;
		mask = ulong.max >> shift;
		count += popCount(bits[i] & mask);

		return count;
	}
}

unittest valueAt {
	Bitmap!256 bmp;
	bmp.bits = [~0x80, ~0x80, ~0x80, ~0x80];

	foreach (i; 0 .. 7) {
		assert(bmp.valueAt(i));
	}

	assert(!bmp.valueAt(7));

	foreach (i; 8 .. 71) {
		assert(bmp.valueAt(i));
	}

	assert(!bmp.valueAt(71));

	foreach (i; 72 .. 135) {
		assert(bmp.valueAt(i));
	}

	assert(!bmp.valueAt(135));

	foreach (i; 136 .. 199) {
		assert(bmp.valueAt(i));
	}

	assert(!bmp.valueAt(199));

	foreach (i; 200 .. 256) {
		assert(bmp.valueAt(i));
	}
}

unittest setFirst {
	Bitmap!256 bmp;
	bmp.bits = [~0x80, ~0x80, ~0x80, ~0x80];

	void checkBitmap(ulong a, ulong b, ulong c, ulong d) {
		assert(bmp.bits[0] == a);
		assert(bmp.bits[1] == b);
		assert(bmp.bits[2] == c);
		assert(bmp.bits[3] == d);
	}

	checkBitmap(~0x80, ~0x80, ~0x80, ~0x80);

	bmp.setFirst();
	checkBitmap(~0, ~0x80, ~0x80, ~0x80);

	bmp.setFirst();
	checkBitmap(~0, ~0, ~0x80, ~0x80);

	bmp.setFirst();
	checkBitmap(~0, ~0, ~0, ~0x80);

	bmp.setFirst();
	checkBitmap(~0, ~0, ~0, ~0);
}

unittest findValue {
	Bitmap!256 bmp1, bmp2;
	bmp1.bits = [0x80, 0x80, 0x80, 0x80];
	bmp2.bits = [~0x80, ~0x80, ~0x80, ~0x80];

	foreach (i; 0 .. 8) {
		assert(bmp1.findSet(i) == 7);
		assert(bmp2.findClear(i) == 7);
		assert(bmp1.findSetBackward(i) == -1);
		assert(bmp2.findClearBackward(i) == -1);
	}

	foreach (i; 8 .. 72) {
		assert(bmp1.findSet(i) == 71);
		assert(bmp2.findClear(i) == 71);
		assert(bmp1.findSetBackward(i) == 7);
		assert(bmp2.findClearBackward(i) == 7);
	}

	foreach (i; 72 .. 136) {
		assert(bmp1.findSet(i) == 135);
		assert(bmp2.findClear(i) == 135);
		assert(bmp1.findSetBackward(i) == 71);
		assert(bmp2.findClearBackward(i) == 71);
	}

	foreach (i; 136 .. 200) {
		assert(bmp1.findSet(i) == 199);
		assert(bmp2.findClear(i) == 199);
		assert(bmp1.findSetBackward(i) == 135);
		assert(bmp2.findClearBackward(i) == 135);
	}

	foreach (i; 200 .. 256) {
		assert(bmp1.findSet(i) == 256);
		assert(bmp2.findClear(i) == 256);
		assert(bmp1.findSetBackward(i) == 199);
		assert(bmp2.findClearBackward(i) == 199);
	}
}

unittest nextFreeRange {
	Bitmap!256 bmp;
	bmp.bits = [0x0fffffffffffffc7, 0x00ffffffffffffc0, 0x00000003ffc00000,
	            0xff00000000000000];

	uint index;
	uint length;

	assert(bmp.nextFreeRange(0, index, length));
	assert(index == 3);
	assert(length == 3);

	assert(bmp.nextFreeRange(index + length, index, length));
	assert(index == 60);
	assert(length == 10);

	assert(bmp.nextFreeRange(index + length, index, length));
	assert(index == 120);
	assert(length == 30);

	assert(bmp.nextFreeRange(index + length, index, length));
	assert(index == 162);
	assert(length == 86);

	// The last one return false because
	// there is no remaining free range.
	assert(!bmp.nextFreeRange(index + length, index, length));
}

unittest setBit {
	Bitmap!256 bmp;

	void checkBitmap(ulong a, ulong b, ulong c, ulong d) {
		assert(bmp.bits[0] == a);
		assert(bmp.bits[1] == b);
		assert(bmp.bits[2] == c);
		assert(bmp.bits[3] == d);
	}

	checkBitmap(0, 0, 0, 0);

	bmp.setBit(0);
	checkBitmap(1, 0, 0, 0);

	// Dobule set does nothing.
	bmp.setBit(0);
	checkBitmap(1, 0, 0, 0);

	bmp.setBit(3);
	checkBitmap(9, 0, 0, 0);

	bmp.setBit(42);
	checkBitmap(0x0000040000000009, 0, 0, 0);

	bmp.setBit(63);
	checkBitmap(0x8000040000000009, 0, 0, 0);

	bmp.clearBit(0);
	checkBitmap(0x8000040000000008, 0, 0, 0);

	// Double clear does nothing.
	bmp.clearBit(0);
	checkBitmap(0x8000040000000008, 0, 0, 0);

	bmp.setBit(64);
	checkBitmap(0x8000040000000008, 1, 0, 0);

	bmp.setBit(255);
	checkBitmap(0x8000040000000008, 1, 0, 0x8000000000000000);
}

unittest setRange {
	Bitmap!256 bmp;

	void checkBitmap(ulong a, ulong b, ulong c, ulong d) {
		assert(bmp.bits[0] == a);
		assert(bmp.bits[1] == b);
		assert(bmp.bits[2] == c);
		assert(bmp.bits[3] == d);
	}

	checkBitmap(0, 0, 0, 0);

	bmp.setRange(3, 3);
	checkBitmap(0x38, 0, 0, 0);

	bmp.setRange(60, 10);
	checkBitmap(0xf000000000000038, 0x3f, 0, 0);

	bmp.setRange(120, 128);
	checkBitmap(0xf000000000000038, 0xff0000000000003f, 0xffffffffffffffff,
	            0x00ffffffffffffff);

	bmp.clearRange(150, 12);
	checkBitmap(0xf000000000000038, 0xff0000000000003f, 0xfffffffc003fffff,
	            0x00ffffffffffffff);

	bmp.setRange(0, 256);
	checkBitmap(~0, ~0, ~0, ~0);

	bmp.clearRange(3, 3);
	checkBitmap(~0x38, ~0, ~0, ~0);

	bmp.clearRange(60, 10);
	checkBitmap(0x0fffffffffffffc7, ~0x3f, ~0, ~0);

	bmp.clearRange(120, 128);
	checkBitmap(0x0fffffffffffffc7, 0x00ffffffffffffc0, 0, 0xff00000000000000);

	bmp.setRange(150, 12);
	checkBitmap(0x0fffffffffffffc7, 0x00ffffffffffffc0, 0x00000003ffc00000,
	            0xff00000000000000);

	bmp.clearRange(0, 256);
	checkBitmap(0, 0, 0, 0);
}

unittest countBits {
	Bitmap!256 bmp;
	foreach (i; 0 .. 128) {
		assert(bmp.countBits(i, 0) == 0);
		assert(bmp.countBits(i, 19) == 0);
		assert(bmp.countBits(i, 48) == 0);
		assert(bmp.countBits(i, 64) == 0);
		assert(bmp.countBits(i, 99) == 0);
		assert(bmp.countBits(i, 128) == 0);
	}

	bmp.bits = [-1, -1, -1, -1];
	foreach (i; 0 .. 128) {
		assert(bmp.countBits(i, 0) == 0);
		assert(bmp.countBits(i, 19) == 19);
		assert(bmp.countBits(i, 48) == 48);
		assert(bmp.countBits(i, 64) == 64);
		assert(bmp.countBits(i, 99) == 99);
		assert(bmp.countBits(i, 128) == 128);
	}

	bmp.bits = [0xaaaaaaaaaaaaaaaa, 0xaaaaaaaaaaaaaaaa, 0xaaaaaaaaaaaaaaaa,
	            0xaaaaaaaaaaaaaaaa];
	foreach (i; 0 .. 128) {
		assert(bmp.countBits(i, 0) == 0);
		assert(bmp.countBits(i, 19) == 9 + (i % 2));
		assert(bmp.countBits(i, 48) == 24);
		assert(bmp.countBits(i, 64) == 32);
		assert(bmp.countBits(i, 99) == 49 + (i % 2));
		assert(bmp.countBits(i, 128) == 64);
	}
}
