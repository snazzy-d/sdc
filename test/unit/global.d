static int g;

struct S {
	int x;
}

static S gs;

unittest global_rvalue_and_assign {
	g = 0;
	assert(g == 0);

	g = 7;
	assert(g == 7);

	g = g + 1;
	assert(g == 8);
}

unittest global_address {
	g = 0;
	int* p = &g;
	assert(p is &g);

	*p = 11;
	assert(g == 11);
	assert(*&g == 11);
	assert(*p == 11);

	*&g = 13;
	assert(g == 13);
	assert(*p == 13);
}

unittest global_load_peel {
	g = 0;
	int* p = &*(&g);
	*p = 21;
	assert(g == 21);
}

unittest global_field {
	gs.x = 3;
	assert(gs.x == 3);

	S* p = &gs;
	p.x = 9;
	assert(gs.x == 9);
}

unittest global_compound_assign {
	g = 10;
	g += 3;
	assert(g == 13);
	g -= 1;
	assert(g == 12);
}
