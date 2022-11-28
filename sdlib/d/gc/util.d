module d.gc.util;

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
