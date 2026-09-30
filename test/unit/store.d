struct S {
	int x;
}

unittest simple_assign {
	int a = 0;
	a = 7;
	assert(a == 7);

	a = a + 1;
	assert(a == 8);
}

unittest assign_through_load {
	int a = 0;
	int* p = &a;
	*p = 11;
	assert(a == 11);
	assert(*p == 11);
}

unittest assign_peeled_address_of_load {
	int a = 0;
	int* p = &a;
	*&*p = 13;
	assert(a == 13);
}

unittest assign_field {
	S s;
	s.x = 3;
	assert(s.x == 3);

	S* ps = &s;
	ps.x = 9;
	assert(s.x == 9);
}

unittest assign_index {
	int[2] a;
	a[0] = 1;
	a[1] = 2;
	assert(a[0] == 1);
	assert(a[1] == 2);
}

unittest chained_assign {
	int a, b;
	a = b = 5;
	assert(a == 5);
	assert(b == 5);
}

unittest compound_assign {
	int a = 10;
	a += 3;
	assert(a == 13);
	a -= 1;
	assert(a == 12);
}

unittest assign_through_double_load {
	int a = 0;
	int* p = &a;
	int** pp = &p;
	**pp = 42;
	assert(a == 42);
}
