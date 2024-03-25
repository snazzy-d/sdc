int add(int a, int b) {
	return a + b;
}

unittest add {
	int function(int, int) f0 = add;
	assert(f0(25, 12) == 37);

	int function(int, int) f1 = &add;
	assert(f1(30, 2) == 32);
}
