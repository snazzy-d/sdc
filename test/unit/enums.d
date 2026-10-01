enum int Small = 42;
enum int Zero = 0;

unittest enum_values {
	assert(Zero == 0);
	assert(Small == 42);
}

enum {
	A,
	B,
	C = D + B,
	D = F - A,
	E = 40,
	F,
}

unittest anonymous_enum_values {
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

unittest named_enum_values {
	assert(Foo.Fizz == 0);
	assert(Foo.Pion == 1);
	assert(Foo.Bar == 42);
	assert(Foo.Baz == 41);
	assert(Foo.Qux == 40);
	assert(Foo.Buzz == 41);
}

unittest enum_vrp {
	ubyte b = Small;
	assert(b == 42);

	ubyte z = Zero;
	assert(z == 0);

	ubyte e = E;
	assert(e == 40);

	ubyte fb = Foo.Bar;
	assert(fb == 42);
}
