template Identity(T)
		if (SomeCondition!T) {
	alias Identity = T;
}

alias TplAlias(alias A, T = TT) =
	Tpl!(A, T);

alias TplAlias(
		alias A, T = DefaultType) =
	Tpl!(A, T, false);

enum Foo {
	Bar, // comment!
}

void foo(int[] args...) {}
