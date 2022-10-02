taggedClassRef!(
	// sdfmt off
	Foo, "foo",
	bool, "bar", 1,
	// sdfmt on
);

// sdfmt off
auto fun() {
	fun();
}
// sdfmt on

// sdfmt off
auto fun() {
	Foo(bar);
}
// sdfmt on

// sdfmt off
struct OneLiner { int a; }
// sdfmt on

auto unterminatedSfmtOff() {
	// sdfmt off
	return Whatever();
}
