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

void* refConstValue(ref const(int) x) {
	return cast(void*) &x;
}

void* refConstPointer(ref const(int*) x) {
	return cast(void*) &x;
}

void* refConstNestedPointer(ref const(int**) x) {
	return cast(void*) &x;
}

void* refConstSlice(ref const(int[]) x) {
	return cast(void*) &x;
}

unittest ref_argument_qualifier {
	// An argument is passed by ref if nothing can be written through the
	// parameter that is not valid for the argument.
	int i = 1;
	immutable(int) ii = 2;
	assert(refConstValue(i) is cast(void*) &i);
	assert(refConstValue(ii) is cast(void*) &ii);

	int* p = &i;
	int** pp = &p;
	int[] s = [1, 2];
	assert(refConstPointer(p) is cast(void*) &p);
	assert(refConstNestedPointer(pp) is cast(void*) &pp);
	assert(refConstSlice(s) is cast(void*) &s);
}

int bindExact(ref int* x) {
	return 1;
}

int bindExact(const(int)* x) {
	return 2;
}

int bindConst(ref const(int*) x) {
	return 1;
}

int bindConst(const(int)* x) {
	return 2;
}

unittest ref_argument_overload {
	// A ref overload is picked when the argument can be passed by ref.
	int i;
	int* p = &i;
	assert(bindExact(p) == 1);
	assert(bindConst(p) == 1);
}

int bindPointer(ref const(int)* x) {
	return 1;
}

int bindPointer(const(int)* x) {
	return 2;
}

unittest ref_argument_overload_value {
	// Through a reference to const(int)*, a pointer to immutable data could
	// be stored in the argument, so it is passed by value.
	int i;
	int* p = &i;
	assert(bindPointer(p) == 2);
}

int bindShared(ref const(shared(int)) x) {
	return 1;
}

int bindShared(const(shared(int)) x) {
	return 2;
}

unittest ref_argument_shared_overload {
	// Immutable data is accessed differently than shared data, so it cannot
	// be passed by ref as shared and is passed by value.
	immutable(int) i = 1;
	assert(bindShared(i) == 2);
}
