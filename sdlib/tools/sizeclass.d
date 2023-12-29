module tools.sizeclass;

import d.gc.sizeclass;

void printfAlloc(size_t s) {
	import d.gc.util, core.stdc.stdio;
	printf("%lu :\t%lu\t%hhu\n", s, getAllocSize(s), getSizeClass(s));
}

void sampleAllocs() {
	import core.stdc.stdio;
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

void printAllSizeClasses() {
	computeSizeClass((uint id, uint grp, uint delta, uint ndelta) {
		import core.stdc.stdio;
		printf(
			"size class id: %d\tgroup: %d\tdelta: %d\tndelta: %d\tmax size: 0x%lx\n",
			id, grp, delta, ndelta, (1UL << grp) + ndelta * (1UL << delta));
	});

	import core.stdc.stdio;
	printf("total: %d\tsmall: %d\tlookup: %d\n", ClassCount.Total,
	       ClassCount.Small, ClassCount.Lookup);
}

void printBinInfos() {
	import core.stdc.stdio;
	printf(
		"| Size class | Element size | Pages | Slot count | Multiplier | Shift | Appendable / Destructible | Marks inline | Dense |\n"
	);
	printf(
		"| ---------: | -----------: | ----: | ---------: | ---------: | ----: | :-----------------------: | :----------: | :---: |\n"
	);

	auto bins = getBinInfos();
	foreach (i, b; bins) {
		printf(
			"| %d | %hu | %hhu | %hu | %hu | %hhu | %c | %c | %c |\n",
			i,
			b.itemSize,
			b.npages,
			b.nslots,
			b.mul,
			b.shift,
			b.supportsMetadata ? 'Y' : 'N',
			b.supportsInlineMarking ? 'Y' : 'N',
			b.dense ? 'Y' : 'N'
		);
	}
}

void main() {
	printBinInfos();
}
