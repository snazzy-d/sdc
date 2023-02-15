module d.gc.sizeclass;

import d.gc.spec;

/**
 * Designing a good allocator require to balance external
 * and internal fragmentation. Allocating exactly the amount
 * of memory requested by the user would ensure internal
 * fragmentation remains at zero - not space would be wasted
 * over allocating - but there would be too many allocations
 * with a unique size, which cases external fragmentation.
 * On the other hand, over allocating too much, for instance
 * by allocating the next power of 2 bytes, causes internal
 * fragmentation.
 * 
 * We want to keep fragmentation at a minimum so that we can
 * minimize the amount of memory that is wasted, which in turn
 * translates into better performances as teh pressure caches
 * and TLB is reduced.
 * 
 * As a compromise, the GC rounds up the requested allocation
 * to the closest size of the form `(4 + delta) << shift`
 * where delta is in the [0 .. 4) range. Each allocation is
 * then associated with a bin based oe the required allocation
 * size. This binning is a good compromise between internal
 * and external fragmentation in typical workloads.
 * 
 * The smallest possible delta is bounded by the Quantum.
 * This ensures that any allocation is Quantum aligned.
 * 
 * Size classes bellow 4 * Quantum are know as Tiny. Tiny
 * classes are special cased so finer granularity can be
 * provided at that level.
 */
enum ClassCount {
	Tiny = getTinyClassCount(),
	Small = getSmallClassCount(),
	Large = getLargeClassCount(),
	Total = getTotalClassCount(),
	Lookup = getLookupClassCount(),
}

enum SizeClass {
	Tiny = getSizeFromClass(ClassCount.Tiny - 1),
	Small = getSizeFromClass(ClassCount.Small - 1),
	Large = getSizeFromClass(ClassCount.Large - 1),
}

enum MaxTinySize = 4 * Quantum;

size_t getAllocSize(size_t size) {
	if (size < MaxTinySize) {
		return (size + QuantumMask) & ~QuantumMask;
	}

	import d.gc.util;
	auto shift = log2floor(size - 1) - 2;

	return (((size - 1) >> shift) + 1) << shift;
}

unittest getAllocSize {
	assert(getAllocSize(0) == 0);

	size_t[] boundaries = [Quantum, 2 * Quantum, 3 * Quantum, 32, 40, 48, 56,
	                       64, 80, 96, 112, 128, 160, 192, 224, 256, 320];

	size_t s = 1;
	foreach (b; boundaries) {
		if (b <= s) {
			continue;
		}

		while (s <= b) {
			assert(getAllocSize(s) == b);
			s++;
		}
	}
}

/**
 * FIXME: Differentiate size class and binID.
 * Large size classes don't have a bin associated, and
 * we may want to shard lower bins at some point
 * which will cuase several bin to use the same size class.
 */
ubyte getBinID(size_t size) {
	return getSizeClass(size);
}

ubyte getSizeClass(size_t size) {
	if (size < MaxTinySize) {
		auto ret = ((size + QuantumMask) >> LgQuantum) - 1;

		assert(size == 0 || ret < ubyte.max);
		return ret & 0xff;
	}

	import d.gc.util;
	auto shift = log2floor(size - 1) - 2;
	auto mod = (size - 1) >> shift;
	auto ret = 4 * (shift - LgQuantum) + mod;

	assert(ret < ubyte.max);
	return ret & 0xff;
}

unittest getSizeClass {
	import d.gc.bin;
	assert(getSizeClass(0) == InvalidBinID);

	size_t[] boundaries = [Quantum, 2 * Quantum, 3 * Quantum, 32, 40, 48, 56,
	                       64, 80, 96, 112, 128, 160, 192, 224, 256, 320];

	uint bid = 0;
	size_t s = 1;
	foreach (b; boundaries) {
		if (b <= s) {
			continue;
		}

		while (s <= b) {
			assert(getSizeClass(s) == bid);
			assert(getAllocSize(s) == getSizeFromClass(bid));
			s++;
		}

		bid++;
	}
}

size_t getSizeFromClass(uint sizeClass) {
	size_t ret;
	if (sizeClass < ClassCount.Small) {
		import d.gc.bin;
		ret = binInfos[sizeClass].itemSize;
	} else {
		auto largeSizeClass = sizeClass - ClassCount.Small;
		auto shift = largeSizeClass / 4 + LgPageSize;
		size_t bits = (largeSizeClass % 4) | 0x04;

		ret = bits << shift;
	}

	// XXX: out contract
	assert(sizeClass == getSizeClass(ret));
	assert(ret == getAllocSize(ret));
	return ret;
}

unittest getSizeFromClass {
	size_t[] boundaries = [Quantum, 2 * Quantum, 3 * Quantum, 32, 40, 48, 56,
	                       64, 80, 96, 112, 128, 160, 192, 224, 256, 320];

	uint bid = 0;
	foreach (b; boundaries) {
		assert(getSizeFromClass(bid++) == b);
	}
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
	ushort itemSize = s & ushort.max;

	ubyte[4] npLookup = [(((s - 1) >> LgPageSize) + 1) & 0xff, 5, 3, 7];

	ubyte shift = delta & 0xff;
	if (grp == delta) {
		auto tag = (ndelta + 1) / 2;
		shift = (delta + tag - 2) & 0xff;
	}

	auto needPages = npLookup[(itemSize >> shift) % 4];

	uint p = needPages;
	ushort slots = ((p << LgPageSize) / s) & ushort.max;

	assert(id < ClassCount.Small);
	bins[id] = BinInfo(itemSize, shift, needPages, slots);
}

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
		if (grp <= LgQuantum) {
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
	foreach (i; 0 .. 3) {
		fun(id++, LgQuantum, LgQuantum, i);
	}

	// Most size classes falls here.
	foreach (uint grp; LgQuantum + 2 .. 8 * size_t.sizeof) {
		foreach (i; 0 .. 4) {
			fun(id++, grp, grp - 2, i);
		}
	}

	// We want to be able to store the binID in a byte.
	assert(id <= ubyte.max);
}

void printfAlloc(size_t s) {
	import d.gc.util, core.stdc.stdio;
	printf("%lu :\t%lu\t%hhu\n", s, getAllocSize(s), getSizeClass(s));
}

void main() {
	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		import core.stdc.stdio;
		printf(
			"size class id: %d\tgroup: %d\tdelta: %d\tndelta: %d\tmax size: 0x%lx\n",
			id, grp, delta, ndelta, (1UL << grp) + ndelta * (1UL << delta));
	});

	import core.stdc.stdio;
	printf("total: %d\tsmall: %d\tlarge: %d\tlookup: %d\n", ClassCount.Total,
	       ClassCount.Small, ClassCount.Large, ClassCount.Lookup);

	auto bins = getBinInfos();

	printf("bins:\n");
	foreach (i; 0 .. ClassCount.Small) {
		auto b = bins[i];
		printf("id: %d\tsize: %hd\tneedPages: %hhd\tslots: %hd\n", i,
		       b.itemSize, b.needPages, b.slots);
	}

	printf("allocs:\n");
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
