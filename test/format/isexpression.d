is(Foo);
is(Foo : class);
is(Foo : class, T, U, V);
is(Foo == const);
is(Foo == const, T, U, V);
is(Foo == const T);
is(Foo == const T, U, V);

is(Foo bar);
is(Foo bar : class);
is(Foo bar : class, T, U, V);
is(Foo bar == const);
is(Foo bar == const, T, U, V);
is(Foo bar == const T);
is(Foo bar == const T, U, V);

is(ParameterT : Tpl!(Arg1, Arg2, Arg3),
                Arg1, Arg2, Arg3);
is(ParameterT == Tpl!(Arg1, Arg2, Arg3),
                 Arg1, Arg2, Arg3);

is(immutable ParameterT
	: immutable Tpl!Element, Element);
is(immutable ParameterT
	== immutable Tpl!Element, Element);

is(immutable ParameterT
	: immutable Tpl!(Element1, Element2, Element3),
	  Element1, Element2, Element3);

is(immutable ParameterT
	== immutable Tpl!(Element1, Element2, Element3),
	   Element1, Element2, Element3);
