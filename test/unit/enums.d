enum {
	A,
	B,
	C = F + B,
	D,
	E = 42,
	F,
}

unittest anonymousEnumValues {
	assert(A == 0);
	assert(B == 1);
	assert(C == 44);
	assert(D == 45);
	assert(E == 42);
	assert(F == 43);
}

enum X {
	A,
	B,
	C = F + B,
	D,
	E = 42,
	F,
}

unittest namedEnumValues {
	assert(X.A == 0);
	assert(X.B == 1);
	assert(X.C == 44);
	assert(X.D == 45);
	assert(X.E == 42);
	assert(X.F == 43);
}
