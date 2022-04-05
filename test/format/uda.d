@delegateUDA!(
	(ref a) => a.type != Type.Toe)
Foo bar;

@templateUda!Bang
@templateUDA!(Foo, Bar)
struct S {}

static foreach (T; Ts)
	@templateUda!T
	void foo(T t) {}
