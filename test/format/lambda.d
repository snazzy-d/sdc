bool fun() {
	match!(
		(A _) @system nothrow pure synchronized =>
			foo.bar.buzz.map!(i => j)
				> 0,
		(B _) =>
			foo.bar.buzz.map!(i => j)
				> 0,
		(C _) => true, (D _) => false);

	return (() @trusted =>
		cast(E[]) result)();
}
