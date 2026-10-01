struct S {
	int x;
	int y;
}

class C {
	int x;
}

unittest field_lvalue {
	S s;
	s.x = 1;
	s.y = 2;
	assert(s.x == 1);
	assert(s.y == 2);

	int* p = &s.y;
	assert(p is &s.y);
	*p = 9;
	assert(s.y == 9);
	assert(*&s.x == 1);
}

unittest field_class {
	C c = new C();
	c.x = 5;
	assert(c.x == 5);
}

unittest field_slice {
	int[2] a;
	a[0] = 1;
	a[1] = 2;
	int[] s = a[0 .. a.length];
	assert(s.length == 2);
	assert(s.ptr is &a[0]);
}

S pair() {
	S s;
	s.x = 3;
	s.y = 4;
	return s;
}

unittest extract_rvalue_field {
	assert(pair().x == 3);
	assert(pair().y == 4);
}
