union F1 {
	float f;
	uint i;
}

union F2 {
	float f;
	uint[2] i;
}

unittest union_init {
	F1 f1;
	assert(f1.i == 0x7fc00000);

	F2 f2;
	assert(f2.i[0] == 0x7fc00000);
	assert(f2.i[1] == 0);
}
