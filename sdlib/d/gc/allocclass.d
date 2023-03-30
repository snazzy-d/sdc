module d.gc.allocclass;

ubyte getAllocClass(size_t pages) {
	if (pages <= 8) {
		auto ret = pages - 1;

		assert(pages == 0 || ret < ubyte.max);
		return ret & 0xff;
	}

	import d.gc.util;
	auto shift = log2floor(pages - 1) - 2;
	auto mod = (pages - 1) >> shift;
	auto ret = 4 * shift + mod;

	assert(ret < ubyte.max);
	return ret & 0xff;
}

unittest getAllocClass {
	import d.gc.bin;
	assert(getAllocClass(0) == 0xff);

	uint[] boundaries =
		[1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56, 64,
		 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512];

	uint ac = 0;
	uint s = 1;
	foreach (b; boundaries) {
		while (s <= b) {
			assert(getAllocClass(s) == ac);
			s++;
		}

		ac++;
	}
}

ubyte getFreeSpaceClass(size_t pages) {
	return (getAllocClass(pages + 1) - 1) & 0xff;
}

unittest getFreeSpaceClass {
	import d.gc.bin;
	assert(getFreeSpaceClass(0) == 0xff);

	uint[] boundaries =
		[1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56, 64,
		 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512];

	uint fc = -1;
	uint s = 1;
	foreach (b; boundaries) {
		while (s < b) {
			assert(getFreeSpaceClass(s) == fc);
			s++;
		}

		fc++;
	}
}
