int g;

ref int slot() {
	return g;
}

int value() {
	return 9;
}

unittest call_value {
	assert(value() == 9);
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
