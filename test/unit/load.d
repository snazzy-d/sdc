struct S {
	int x;
}

unittest load_store {
	int a = 7;
	int* p = &a;

	assert(*p == 7);

	*p = 10;
	assert(*p == 10);
	assert(a == 10);
}

unittest address_of_load {
	int a = 7;
	int* p = &a;

	int* q = &*p;
	assert(q is p);

	*q = 21;
	assert(a == 21);
	assert(*p == 21);
}

unittest load_of_address {
	int a = 21;
	assert(*&a == 21);

	*&a = 42;
	assert(a == 42);
}

unittest double_load {
	int a = 0;
	int* p = &a;
	int** pp = &p;

	**pp = 42;
	assert(a == 42);
	assert(*p == 42);
	assert(**pp == 42);
}

unittest pointer_autoderef_field {
	S s;
	s.x = 0;

	S* ps = &s;
	ps.x = 42;

	assert(s.x == 42);
	assert((*ps).x == 42);
	assert(ps.x == 42);
}
