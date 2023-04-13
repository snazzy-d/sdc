module d.gc.util;

T min(T)(T a, T b) {
	return a <= b ? a : b;
}

unittest min {
	assert(min(0, 0) == 0);
	assert(min(0, -1) == -1);
	assert(min(-1, 0) == -1);
	assert(min(123, 456) == 123);
}

T max(T)(T a, T b) {
	return a >= b ? a : b;
}

unittest max {
	assert(max(0, 0) == 0);
	assert(max(0, -1) == 0);
	assert(max(-1, 0) == 0);
	assert(max(123, 456) == 456);
}

ubyte log2floor(T)(T x) {
	if (x == 0) {
		return 0;
	}

	import sdc.intrinsics;
	enum S = T.sizeof * 8;
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

bool isPow2(T)(T x) {
	import sdc.intrinsics;
	return popCount(x) == 1;
}

unittest isPow2 {
	assert(isPow2(1));
	assert(isPow2(2));
	assert(isPow2(4));
	assert(isPow2(8));
	assert(isPow2(16));
	assert(isPow2(32));
	assert(isPow2(64));
	assert(isPow2(128));
	assert(isPow2(256));
	assert(isPow2(512));
	assert(isPow2(1024));

	assert(!isPow2(0));
	assert(!isPow2(3));
	assert(!isPow2(-1));
	assert(!isPow2(42));
}

T modUp(T)(T n, T mod) {
	n += mod - 1;
	return (n % mod) + 1;
}

unittest modUp {
	assert(modUp(0, 1) == 1);
	assert(modUp(1, 1) == 1);
	assert(modUp(42, 64) == 42);
	assert(modUp(127, 64) == 63);

	foreach (x; 2 .. 256) {
		assert(modUp(0, x) == x);
		assert(modUp(1, x) == 1);
		assert(modUp(x - 1, x) == x - 1);
		assert(modUp(x, x) == x);
	}
}

size_t alignDown(size_t size, size_t alignment) {
	// FIXME: in contract.
	assert(isPow2(alignment));
	auto ret = size & -alignment;

	// FIXME: out contract.
	assert(ret <= size);
	return ret;
}

void* alignDown(const void* ptr, size_t alignment) {
	// FIXME: in contract.
	assert(isPow2(alignment));
	return cast(void*) alignDown(cast(size_t) ptr, alignment);
}

size_t alignDownOffset(size_t size, size_t alignment) {
	return size - alignDown(size, alignment);
}

size_t alignDownOffset(const void* ptr, size_t alignment) {
	return alignDownOffset(cast(size_t) ptr, alignment);
}

bool isAligned(size_t size, size_t alignment) {
	return alignDown(size, alignment) == size;
}

bool isAligned(const void* ptr, size_t alignment) {
	return alignDown(ptr, alignment) is ptr;
}

unittest alignDown {
	static testAlignDown(size_t size, size_t alignment, size_t expected) {
		assert(alignDown(size, alignment) == expected);
		assert(alignDown(cast(void*) size, alignment) == cast(void*) expected);

		auto offset = size - expected;
		assert(alignDownOffset(size, alignment) == offset);
		assert(alignDownOffset(cast(void*) size, alignment) == offset);

		auto aligned = offset == 0;
		assert(isAligned(size, alignment) == aligned);
		assert(isAligned(cast(void*) size, alignment) == aligned);
	}

	testAlignDown(128, 1, 128);
	testAlignDown(128, 2, 128);
	testAlignDown(128, 4, 128);
	testAlignDown(128, 8, 128);

	testAlignDown(129, 1, 129);
	testAlignDown(129, 2, 128);
	testAlignDown(129, 4, 128);
	testAlignDown(129, 8, 128);

	testAlignDown(130, 1, 130);
	testAlignDown(130, 2, 130);
	testAlignDown(130, 4, 128);
	testAlignDown(130, 8, 128);

	testAlignDown(131, 1, 131);
	testAlignDown(131, 2, 130);
	testAlignDown(131, 4, 128);
	testAlignDown(131, 8, 128);

	testAlignDown(132, 1, 132);
	testAlignDown(132, 2, 132);
	testAlignDown(132, 4, 132);
	testAlignDown(132, 8, 128);

	testAlignDown(133, 1, 133);
	testAlignDown(133, 2, 132);
	testAlignDown(133, 4, 132);
	testAlignDown(133, 8, 128);

	testAlignDown(134, 1, 134);
	testAlignDown(134, 2, 134);
	testAlignDown(134, 4, 132);
	testAlignDown(134, 8, 128);

	testAlignDown(135, 1, 135);
	testAlignDown(135, 2, 134);
	testAlignDown(135, 4, 132);
	testAlignDown(135, 8, 128);

	testAlignDown(136, 1, 136);
	testAlignDown(136, 2, 136);
	testAlignDown(136, 4, 136);
	testAlignDown(136, 8, 136);

	foreach (s; 128 .. 137) {
		for (size_t a = 16; a <= 128; a <<= 1) {
			testAlignDown(s, a, 128);
		}

		for (size_t a = 256; a <= 1024 * 1024 * 1024; a <<= 1) {
			testAlignDown(s, a, 0);
		}
	}

	for (size_t a = 1, x = -1; a > 0; a <<= 1, x <<= 1) {
		testAlignDown(-1, a, x);
	}
}

size_t alignUp(size_t size, size_t alignment) {
	// FIXME: in contract.
	assert(isPow2(alignment));
	auto ret = (size + alignment - 1) & (~alignment + 1);

	// FIXME: out contract.
	assert(ret >= size);
	return ret;
}

void* alignUp(const void* ptr, size_t alignment) {
	// FIXME: in contract.
	assert(isPow2(alignment));
	return cast(void*) alignUp(cast(size_t) ptr, alignment);
}

size_t alignUpOffset(size_t size, size_t alignment) {
	return alignUp(size, alignment) - size;
}

size_t alignUpOffset(const void* ptr, size_t alignment) {
	return alignUpOffset(cast(size_t) ptr, alignment);
}

unittest alignUp {
	static testAlignUp(size_t size, size_t alignment, size_t expected) {
		assert(alignUp(size, alignment) == expected);
		assert(alignUp(cast(void*) size, alignment) == cast(void*) expected);

		auto offset = expected - size;
		assert(alignUpOffset(size, alignment) == offset);
		assert(alignUpOffset(cast(void*) size, alignment) == offset);

		auto aligned = offset == 0;
		assert(isAligned(size, alignment) == aligned);
		assert(isAligned(cast(void*) size, alignment) == aligned);
	}

	testAlignUp(120, 1, 120);
	testAlignUp(120, 2, 120);
	testAlignUp(120, 4, 120);
	testAlignUp(120, 8, 120);

	testAlignUp(121, 1, 121);
	testAlignUp(121, 2, 122);
	testAlignUp(121, 4, 124);
	testAlignUp(121, 8, 128);

	testAlignUp(122, 1, 122);
	testAlignUp(122, 2, 122);
	testAlignUp(122, 4, 124);
	testAlignUp(122, 8, 128);

	testAlignUp(123, 1, 123);
	testAlignUp(123, 2, 124);
	testAlignUp(123, 4, 124);
	testAlignUp(123, 8, 128);

	testAlignUp(124, 1, 124);
	testAlignUp(124, 2, 124);
	testAlignUp(124, 4, 124);
	testAlignUp(124, 8, 128);

	testAlignUp(125, 1, 125);
	testAlignUp(125, 2, 126);
	testAlignUp(125, 4, 128);
	testAlignUp(125, 8, 128);

	testAlignUp(126, 1, 126);
	testAlignUp(126, 2, 126);
	testAlignUp(126, 4, 128);
	testAlignUp(126, 8, 128);

	testAlignUp(127, 1, 127);
	testAlignUp(127, 2, 128);
	testAlignUp(127, 4, 128);
	testAlignUp(127, 8, 128);

	testAlignUp(128, 1, 128);
	testAlignUp(128, 2, 128);
	testAlignUp(128, 4, 128);
	testAlignUp(128, 8, 128);

	foreach (s; 120 .. 129) {
		for (size_t a = 16; a <= 128; a <<= 1) {
			testAlignUp(s, a, 128);
		}

		for (size_t a = 128; a <= 1024 * 1024 * 1024; a <<= 1) {
			testAlignUp(s, a, a);
		}
	}
}
