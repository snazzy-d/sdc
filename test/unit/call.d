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
	// A reference converts as a pointer to what it refers to, so immutable
	// data can be passed by ref as const shared.
	immutable(int) i = 1;
	assert(bindShared(i) == 1);
}

class ViewBase {}
class ViewDerived : ViewBase {}

int bindView(ref const(ViewBase) x) {
	return 1;
}

int bindView(const(ViewBase) x) {
	return 2;
}

unittest ref_argument_view_overload {
	// A reference converts as a pointer to what it refers to, so a derived
	// class can be passed by ref as a const base.
	ViewDerived d = new ViewDerived();
	assert(bindView(d) == 1);
}

void* refConstUint(ref const(uint) x) {
	return cast(void*) &x;
}

void* refConstSharedUint(ref const(shared(uint)) x) {
	return cast(void*) &x;
}

void* refConstViewBase(ref const(ViewBase) x) {
	return cast(void*) &x;
}

ref const(uint) returnConstUint(ref immutable(int) x) {
	return x;
}

ref const(shared(uint)) returnConstSharedUint(ref shared(int) x) {
	return x;
}

ref const(ViewBase) returnConstViewBase(ref ViewDerived x) {
	return x;
}

unittest ref_view_type {
	// A reference converts as a pointer to what it refers to, so data can be
	// bound by ref as another type with the same representation, as long as
	// nothing can be written through it.
	int i = -1;
	immutable(int) ii = -1;
	shared(int) si = -1;
	auto d = new ViewDerived();
	assert(refConstUint(i) is cast(void*) &i);
	assert(refConstUint(ii) is cast(void*) &ii);
	assert(refConstSharedUint(si) is cast(void*) &si);
	assert(refConstSharedUint(ii) is cast(void*) &ii);
	assert(refConstViewBase(d) is cast(void*) &d);

	assert(cast(void*) &returnConstUint(ii) is cast(void*) &ii);
	assert(returnConstUint(ii) == uint.max);
	assert(cast(void*) &returnConstSharedUint(si) is cast(void*) &si);
	assert(cast(void*) &returnConstViewBase(d) is cast(void*) &d);

	int[] a = [-1, 2];
	foreach (k, ref const(uint) e; a) {
		assert(cast(void*) &e is cast(void*) &a[k]);
	}

	shared(int)[] sa = [-1, 2];
	foreach (k, ref const(shared(uint)) e; sa) {
		assert(cast(void*) &e is cast(void*) &sa[k]);
	}

	immutable(int)[] ia = [-1, 2];
	foreach (k, ref const(shared(uint)) e; ia) {
		assert(cast(void*) &e is cast(void*) &ia[k]);
	}

	ViewDerived[] ds = [d];
	foreach (k, ref const(ViewBase) e; ds) {
		assert(cast(void*) &e is cast(void*) &ds[k]);
	}
}
