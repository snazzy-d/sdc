module d.gc.util;

// XXX: Would require more benchmarks, but it looks like
// it is faster to do it that way than using bsr/bsf ??!?
auto pow2ceil(size_t x) {
	x--;
	x |= x >> 1;
	x |= x >> 2;
	x |= x >> 4;
	x |= x >> 8;
	x |= x >> 16;
	x |= x >> 32;
	x++;

	return x;
}

size_t log2floor(size_t x) {
	if (x == 0) {
		return 0;
	}

	import sdc.intrinsics;
	enum S = size_t.sizeof * 8;
	return S - countLeadingZeros(x) - 1;
}

unittest log2floor {
	assert(log2floor(0) == 0);
	assert(log2floor(1) == 0);
	assert(log2floor(2) == 1);
	assert(log2floor(3) == 1);
	assert(log2floor(4) == 2);
	assert(log2floor(7) == 2);
	assert(log2floor(8) == 3);
	assert(log2floor(15) == 3);
	assert(log2floor(16) == 4);
	assert(log2floor(31) == 4);
	assert(log2floor(32) == 5);
}
