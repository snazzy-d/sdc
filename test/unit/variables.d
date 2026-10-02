unittest local_address {
	int x = 1;
	int* p = &x;

	assert(x == 1);
	assert(*p == 1);

	x = 4;
	assert(x == 4);
	assert(*p == 4);

	*p = 9;
	assert(x == 9);
	assert(*p == 9);
}

unittest global_address {
	static int x = 1;
	int* p = &x;

	assert(x == 1);
	assert(*p == 1);

	x = 4;
	assert(x == 4);
	assert(*p == 4);

	*p = 9;
	assert(x == 9);
	assert(*p == 9);
}

unittest immutable_local_fits {
	immutable int answer = 42;
	ubyte b = answer;
	assert(b == 42);

	immutable int zero = 0;
	ubyte z = zero;
	assert(z == 0);
}

immutable int ganswer = 42;
immutable int gzero = 0;

unittest immutable_global_fits {
	ubyte b = ganswer;
	assert(b == 42);
	ubyte z = gzero;
	assert(z == 0);
}
