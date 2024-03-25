int add(int a, int b) {
	return a + b;
}

unittest add {
	int function(int, int) f0 = add;
	assert(f0(25, 12) == 37);

	int function(int, int) f1 = &add;
	assert(f1(30, 2) == 32);
}

unittest constant {
	static int result = 0;

	static void set(int x) {
		result = x;
	}

	set(3);
	assert(result == 3);

	static void function(int) cstfun0 = set;
	cstfun0(5);
	assert(result == 5);

	static shared void function(int) cstfun1 = set;
	cstfun1(7);
	assert(result == 7);
}
