unittest plus_minus {
	bool b = true;

	// Make sure unary operators promote boolean to int.
	auto plus = +b;
	assert(typeof(plus).sizeof == 4);
	assert(plus == 1);

	auto minus = -b;
	assert(typeof(minus).sizeof == 4);
	assert(minus == -1);

	auto complement = ~b;
	assert(typeof(complement).sizeof == 4);
	assert(complement == -2);

	// Long stay long.
	ulong l = 0x1234567890abcdef;
	assert(+l == 0x1234567890abcdef);
	assert(-l == 0xedcba9876f543211);
	assert(~l == 0xedcba9876f543210);
}
