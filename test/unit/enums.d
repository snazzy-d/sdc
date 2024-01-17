enum {
	A,
	B,
	C = D + B,
	D = F - A,
	E = 40,
	F,
}

unittest anonymousEnumValues {
	assert(A == 0);
	assert(B == 1);
	assert(C == 42);
	assert(D == 41);
	assert(E == 40);
	assert(F == 41);
}

enum Foo {
	Fizz,
	Pion,
	Bar = Baz + Pion,
	Baz = Buzz - Fizz,
	Qux = 40,
	Buzz,
}

unittest namedEnumValues {
	assert(Foo.Fizz == 0);
	assert(Foo.Pion == 1);
	assert(Foo.Bar == 42);
	assert(Foo.Baz == 41);
	assert(Foo.Qux == 40);
	assert(Foo.Buzz == 41);
}
