bool fun() {
	match!(
		(A _) @system nothrow pure synchronized =>
			foo.bar.buzz.map!(i => j)
				> 0,
		(B _) =>
			foo.bar.buzz.map!(i => j)
				> 0,
		(C _) => true,
		(D _) => false,
		function Type(ArgType e) => e,
		function Type(ArgType) => throw
			new Exception("Ooof!"),
		delegate {
			return true;
		},
		(@UDAType("E") A a) => B(a),
		(@(33) int) => 0,
	);

	return (() @trusted =>
		cast(E[]) result)();
}
