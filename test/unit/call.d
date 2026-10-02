int value() {
	return 9;
}

unittest call_value {
	assert(value() == 9);
}

int g;

ref int slot() {
	return g;
}

unittest call_ref_assign {
	g = 0;
	slot() = 4;
	assert(g == 4);
	assert(slot() == 4);
}

unittest call_ref_address {
	g = 1;
	int* p = &slot();
	assert(p is &g);
	*p = 6;
	assert(g == 6);
}

ref int bump(ref int x) {
	x = x + 1;
	return x;
}

unittest ref_return_address {
	int x = 3;
	bump(x);
	assert(x == 4);
	bump(x) = 9;
	assert(x == 9);
}
