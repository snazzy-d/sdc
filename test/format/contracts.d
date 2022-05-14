Value foobar(Value val)
		in(val.kind == SomeKind)
		out(val; val.kind == SomeKind) {
	return val;
}
