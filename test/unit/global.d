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

int tlsValue = 1;
shared int sharedValue = 2;
immutable int immutableValue = 3;

const(shared(int))* sharedValueAddress = &cast(const(shared(int))) sharedValue;
const(int)* immutableValueAddress = &cast(const(int)) immutableValue;

unittest global_cast_address {
	// A cast that refers to a global has the address of the global.
	assert(&cast(const(int)) tlsValue is &tlsValue);
	assert(&cast(const(shared(int))) sharedValue is &sharedValue);
	assert(&cast(const(int)) immutableValue is &immutableValue);

	// This address is a constant when the global is not thread local.
	assert(sharedValueAddress is &sharedValue);
	assert(immutableValueAddress is &immutableValue);
}

enum immutableEnum = immutableValue;

template Identity(int N) {
	enum Identity = N;
}

immutable string immutableCode = "enum mixedIn = 7;";
mixin(immutableCode);

int[immutableValue] immutableSized;

unittest global_evaluate {
	// An immutable global is known at compile time.
	assert(immutableEnum == 3);
	assert(Identity!immutableValue == 3);
	assert(immutableSized.length == 3);
	assert(mixedIn == 7);
}
