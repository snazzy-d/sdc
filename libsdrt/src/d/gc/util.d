module d.gc.util;

// XXX: Would that be faster with bsr/bsf ?
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

auto lg2floor(size_t size) {
	enum S = size_t.sizeof * 8;
	
	// XXX: use bsr/bsf
	for (uint i = 1; i <= S; i++) {
		if (size & (1UL << (S - i))) {
			return S - i;
		}
	}
	
	return 0;
}

auto popcount(uint bmp) {
	enum S = uint.sizeof * 8;
	
	// XXX: use popcnt
	ubyte count = 0;
	for (uint i = 0; i < S; i++) {
		if (bmp & (1 << i)) {
			count++;
		}
	}
	
	return count;
}
