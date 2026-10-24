int value() {
	return 9;
}

unittest call_value {
	assert(value() == 9);
}

int g;

ref int slot() {
	return g;
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

ref int bump(ref int x) {
	x = x + 1;
	return x;
}

ref const(int*) refConstReturn(ref int* p) {
	return p;
}

ref const(shared(int)) refConstSharedReturn(ref immutable(int) x) {
	return x;
}

ref const(shared(int)) refConstSharedFromShared(ref shared(int) x) {
	return x;
}

int* refConstSharedValue(ref const(shared(int)) v) {
	return cast(int*) &v;
}

unittest ref_return_qualifier {
	// What a returned reference refers to can become const, if nothing
	// below can then be written.
	int x = 1;
	int* p = &x;
	assert(cast(void*) &refConstReturn(p) is cast(void*) &p);

	// Immutable data is never written, so it can be accessed as shared.
	immutable(int) i = 2;
	assert(cast(void*) &refConstSharedReturn(i) is cast(void*) &i);
	assert(refConstSharedValue(i) is cast(int*) &i);

	shared(int) si = 3;
	assert(cast(void*) &refConstSharedFromShared(si) is cast(void*) &si);
	assert(refConstSharedValue(si) is cast(int*) &si);
}

unittest ref_return_address {
	int x = 3;
	bump(x);
	assert(x == 4);
	bump(x) = 9;
	assert(x == 9);
}
