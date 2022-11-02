Tpl!(Type1, Type2, Type3, Type4, Type5)
	foo(
		Tpl!(Type1, Type2, Type3, Type4,
		     Type5) bar,
		Tpl!(Type1, Type2, Type3, Type4,
		     Type5) buzz
	) {}

foreach (v; AliasSeq!(
	double(PI),
	float(PI),
	double(PI * 1e-20),
	float(PI * 1e-20),
	double(PI * 1e20),
	float(PI * 1e20)
)) {
	// Do stuff.
}

auto a = [
	[
		"aaaa", "bbbb", "cccc", "dddd",
		"eeee", "ffff", "gggg", "hhhh",
		"iiii", "jjjj", "kkkk", "llll"
	],
	[
		"aaaa", "bbbb", "cccc", "dddd",
		"eeee", "ffff", "gggg", "hhhh",
		"iiii", "jjjj", "kkkk", "llll"
	],
	[
		"aaaa", "bbbb", "cccc", "dddd",
		"eeee", "ffff", "gggg", "hhhh",
		"iiii", "jjjj", "kkkk", "llll"
	],
	[
		"aaaa", "bbbb", "cccc", "dddd",
		"eeee", "ffff", "gggg", "hhhh",
		"iiii", "jjjj", "kkkk", "llll"
	],
];
