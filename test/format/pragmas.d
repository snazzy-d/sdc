pragma(msg, "message!");

pragma(mangle, "foo")
export void foo() {}

static if (condition)
	pragma(mangle, "foo")
	export void foo() {}
