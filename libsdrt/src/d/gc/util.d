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
	for (int i = 1; i <= S; i++) {
		if (size & (1UL << (S - i))) {
			return S - i;
		}
	}
	
	return 0;
}

