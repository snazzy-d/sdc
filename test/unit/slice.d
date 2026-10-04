unittest slice_array {
	int[4] a;
	a[0] = 1;
	a[1] = 2;
	a[2] = 3;
	a[3] = 4;

	int[] s = a[1 .. 3];
	assert(s.length == 2);
	assert(s[0] == 2);
	assert(s[1] == 3);
	s[0] = 9;
	assert(a[1] == 9);
}

unittest slice_of_slice {
	int[4] a;
	a[0] = 1;
	a[1] = 2;
	a[2] = 3;
	a[3] = 4;
	int[] s = a[0 .. 4];
	int[] t = s[1 .. 3];
	assert(t.length == 2);
	assert(t[0] == 2);
	assert(t[1] == 3);
}

unittest slice_pointer {
	int[4] a;
	a[0] = 1;
	a[1] = 2;
	a[2] = 3;
	int* p = &a[0];
	int[] s = p[1 .. 3];
	assert(s.length == 2);
	assert(s[0] == 2);
	assert(s[1] == 3);
}
