unittest index_array {
	int[2] a;
	a[0] = 1;
	a[1] = 2;
	assert(a[0] == 1);
	assert(a[1] == 2);

	int* p = &a[1];
	assert(p is &a[1]);
	*p = 9;
	assert(a[1] == 9);
	assert(*&a[0] == 1);
}

unittest index_pointer_and_slice {
	int[3] a;
	a[0] = 4;
	a[1] = 5;
	a[2] = 6;

	int* p = &a[0];
	assert(*(p + 1) == 5);
	*(p + 1) = 8;
	assert(a[1] == 8);

	// FIXME: Implement slice expressions.
	// int[] s = a[];
	int[] s = a[0 .. a.length];
	assert(s[2] == 6);
	s[2] = 7;
	assert(a[2] == 7);
}

unittest index_ptr_field {
	int[2] a;
	int* q = a.ptr;
	q[0] = 3;
	q[1] = 4;
	assert(a[0] == 3);
	assert(a[1] == 4);
	assert(a.ptr is &a[0]);
}

int[2] pair() {
	int[2] a;
	a[0] = 3;
	a[1] = 4;
	return a;
}

unittest extract_rvalue_array {
	assert(pair()[0] == 3);
	assert(pair()[1] == 4);

	int i = 1;
	assert(pair()[i] == 4);
}
