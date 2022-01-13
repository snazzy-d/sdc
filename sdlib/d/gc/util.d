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

size_t lg2floor(size_t x) {
	if (x == 0) {
		return 0;
	}

	import sdc.intrinsics;
	enum S = size_t.sizeof * 8;
	return S - countLeadingZeros(x) - 1;
}
