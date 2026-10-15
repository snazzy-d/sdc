int fun(int x) {
	return x + 1;
}

unittest function_value {
	// A function is a first class value: naming it in an auto
	// declaration deduces the function type.
	auto f = fun;
	assert(f(41) == 42);
}

int solo(int x) {
	return x + 1;
}

unittest overloadset_singleton {
	// An overload set with a single member resolves to that
	// member when used as a value.
	auto f = solo;
	assert(f(41) == 42);

	// Taking its address is a passthrough.
	auto g = &solo;
	assert(g(41) == 42);
}

int ov(int x) {
	return x + 1;
}

int ov(string s) {
	return 0;
}

int take(int function(int) f) {
	return f(41);
}

unittest overloadset_argument {
	// The parameter's type resolves the set.
	assert(take(ov) == 42);

	// Same through the address-of passthrough.
	assert(take(&ov) == 42);
}

unittest overloadset_typed_declaration {
	// The declared type resolves the set.
	int function(int) f = ov;
	assert(f(41) == 42);

	int function(int) g = &ov;
	assert(g(41) == 42);
}

unittest overloadset_typed_assignment {
	int function(int) f;
	f = ov;
	assert(f(41) == 42);
}

int function(int) pick() {
	return ov;
}

unittest overloadset_return {
	// The return type resolves the set.
	assert(pick()(41) == 42);
}

struct S {
	int base;

	int m(int x) {
		return base + x;
	}
}

unittest overloadset_method {
	// A method set with a single member resolves to a delegate
	// bound to the receiver.
	S s;
	s.base = 40;
	auto d = s.m;
	assert(d(2) == 42);
}
