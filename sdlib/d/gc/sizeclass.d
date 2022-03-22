module d.gc.sizeclass;

import d.gc.spec;

enum ClassCount {
	Tiny = getTinyClassCount(),
	Small = getSmallClassCount(),
	Large = getLargeClassCount(),
	Total = getTotalClassCount(),
	Lookup = getLookupClassCount(),
}

enum SizeClass {
	Small = getSizeFromBinID(ClassCount.Small - 1),
	Large = getSizeFromBinID(ClassCount.Large - 1),
}

size_t getAllocSize(size_t size) {
	if (LgTiny < LgQuantum && size < (1UL << LgQuantum)) {
		// Not the fastest way to handle this.
		import d.gc.util;
		auto s = pow2ceil(size);

		enum T = 1UL << LgTiny;
		return (s < T) ? T : s;
	}

	import d.gc.util;
	auto shift =
		(size < (1UL << LgQuantum + 2)) ? LgQuantum : lg2floor(size - 1) - 2;

	return (((size - 1) >> shift) + 1) << shift;
}

ubyte getBinID(size_t size) {
	if (LgTiny < LgQuantum && size < (1UL << LgQuantum)) {
		// Not the fastest way to handle this.
		import d.gc.util;
		auto ret = lg2floor(pow2ceil(size) >> LgTiny);

		// TODO: out contract.
		assert(ret < ubyte.max);
		return cast(ubyte) ret;
	}

	// Faster way to compute x = lg2floor(pow2ceil(size));
	import d.gc.util;
	auto shift =
		(size < (1UL << (LgQuantum + 2))) ? LgQuantum : lg2floor(size - 1) - 2;

	auto mod = (size - 1) >> shift;
	auto ret = (shift - LgQuantum) * 4 + mod + ClassCount.Tiny;

	// TODO: out contract.
	assert(ret < ubyte.max);
	return cast(ubyte) ret;
}

size_t getSizeFromBinID(uint binID) {
	if (binID < ClassCount.Small) {
		import d.gc.bin;
		auto ret = binInfos[binID].itemSize;

		// XXX: out contract
		assert(binID == getBinID(ret));
		assert(ret == getAllocSize(ret));
		return ret;
	}

	auto largeBinID = binID - ClassCount.Small;
	auto shift = largeBinID / 4 + LgPageSize;
	size_t bits = (largeBinID % 4) | 0x04;

	auto ret = bits << shift;

	// XXX: out contract
	assert(binID == getBinID(ret));
	assert(ret == getAllocSize(ret));
	return ret;
}

auto getBinInfos() {
	import d.gc.bin;
	BinInfo[ClassCount.Small] bins;

	void delegate(uint id, uint grp, uint delta, uint ndelta) dg = void;
	auto dgSt = cast(BinInfoComputerDg*) &dg;

	dgSt.fun = binInfoComputer;
	dgSt.bins = &bins;

	computeSizeClass(dg);

	return bins;
}

private:

enum LgSizeClass {
	LgSmall = LgPageSize + 2,
	LgLarge = LgSmall + 7,
}

// XXX: find a better way to do all this.
// This is kind of convoluted as I want to avoid alloc.
struct BinInfoComputerDg {
	void* bins;
	void* fun;
}

void binInfoComputer(void* binsPtr, uint id, uint grp, uint delta,
                     uint ndelta) {
	import d.gc.bin;
	auto bins = cast(BinInfo*) binsPtr;

	// XXX: 1UL is useless here, but there is a bug in type
	// promotion for >= so we need it.
	auto s = (1UL << grp) + (ndelta << delta);
	if (s >= (1UL << LgSizeClass.LgSmall)) {
		return;
	}

	assert(s < ushort.max);
	auto itemSize = cast(ushort) s;

	ubyte[4] npLookup;

	// XXX: use array initializer.
	npLookup[0] = cast(ubyte) (((s - 1) >> LgPageSize) + 1);
	npLookup[1] = 5;
	npLookup[2] = 3;
	npLookup[3] = 7;

	auto shift = cast(ubyte) delta;
	if (grp == delta) {
		auto tag = (ndelta + 1) / 2;
		shift = cast(ubyte) (delta + tag - 2);
	}

	auto needPages = npLookup[(itemSize >> shift) % 4];

	uint p = needPages;
	auto slots = cast(ushort) ((p << LgPageSize) / s);

	assert(id < ClassCount.Small);
	bins[id] = BinInfo(itemSize, shift, needPages, slots);
}

// 64 bits tiny, 128 bits quantum.
enum LgTiny = 3;
enum LgQuantum = 4;

auto getTotalClassCount() {
	uint count = 0;

	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		count++;
	});

	return count;
}

auto getTinyClassCount() {
	uint count = 0;

	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		if (grp < LgQuantum) {
			count++;
		}
	});

	return count;
}

auto getSmallClassCount() {
	uint count = 0;

	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		if (grp < LgSizeClass.LgSmall) {
			count++;
		}
	});

	return count;
}

auto getLargeClassCount() {
	uint count = 0;

	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		if (grp < LgSizeClass.LgLarge) {
			count++;
		}
	});

	return count + 1;
}

auto getLookupClassCount() {
	uint count = 0;

	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		if (grp < LgPageSize) {
			count++;
		}
	});

	return count + 1;
}

void computeSizeClass(
	void delegate(uint id, uint grp, uint delta, uint ndelta) fun
) {
	uint id = 0;

	// Tiny sizes.
	foreach (grp; LgTiny .. LgQuantum) {
		fun(id++, grp, grp, 0);
	}

	// First group is kind of special.
	foreach (i; 0 .. 3) {
		fun(id++, LgQuantum, LgQuantum, i);
	}

	// Most size classes falls here.
	foreach (grp; LgQuantum + 2 .. SizeofPtr * 8) {
		foreach (i; 0 .. 4) {
			fun(id++, grp, grp - 2, i);
		}
	}

	// We want to be able to store the binID in a byte.
	assert(id <= ubyte.max);
}

void printfAlloc(size_t s) {
	import d.gc.util, core.stdc.stdio;
	printf("%lu :\t%lu\t%hhu\n".ptr, s, getAllocSize(s), getBinID(s));
}

void main() {
	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		import core.stdc.stdio;
		printf("%d\t%d\t%d\t%d\t0x%lx\n".ptr, id, grp, delta, ndelta,
		       (1UL << grp) + ndelta * (1UL << delta));
	});

	import core.stdc.stdio;
	printf("total: %d\tsmall: %d\tlarge: %d\tlookup: %d\n".ptr,
	       ClassCount.Total, ClassCount.Small, ClassCount.Large,
	       ClassCount.Lookup);

	auto bins = getBinInfos();

	printf("bins:\n".ptr);
	foreach (i; 0 .. ClassCount.Small) {
		auto b = bins[i];
		printf("id: %d\tsize: %hd\tneedPages: %hhd\tslots: %hd\n".ptr, i,
		       b.itemSize, b.needPages, b.slots);
	}

	printf("allocs:\n".ptr);
	printfAlloc(0);
	printfAlloc(5);
	printfAlloc(8);
	printfAlloc(9);
	printfAlloc(16);
	printfAlloc(17);
	printfAlloc(32);
	printfAlloc(33);
	printfAlloc(48);
	printfAlloc(49);
	printfAlloc(64);
	printfAlloc(65);
	printfAlloc(80);
	printfAlloc(81);
	printfAlloc(96);
	printfAlloc(97);
	printfAlloc(112);
	printfAlloc(113);
	printfAlloc(128);
	printfAlloc(129);
	printfAlloc(160);
	printfAlloc(161);
	printfAlloc(192);

	printfAlloc(1UL << 63);
	printfAlloc((1UL << 63) + 1);
	printfAlloc((1UL << 63) + (1UL << 61));
	printfAlloc((1UL << 63) + (1UL << 61) + 1);
	printfAlloc((1UL << 63) + (2UL << 61));
	printfAlloc((1UL << 63) + (2UL << 61) + 1);
	printfAlloc((1UL << 63) + (3UL << 61));
	printfAlloc((1UL << 63) + (3UL << 61) + 1);
}
