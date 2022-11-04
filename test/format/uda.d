@delegateUDA!(
	(ref a) => a.type != Type.Toe)
Foo bar;

@templateUda!Bang
@templateUDA!(Foo, Bar)
struct S {}

static foreach (T; Ts)
	@templateUda!T
	void foo(T t) {}

@property
	empty() {}

long foo(
	@ParamUDA("A") @ParamUDA("B") long a
) {
	return a;
}

long foo(@ParamUDA("C") long b,
         @ParamUDA("D") B c) {
	return b - c.b;
}

int delegate(@(42) int i) dg;
