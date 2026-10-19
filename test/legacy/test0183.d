//T compiles:yes
//T has-passed:yes
//T retval:42

struct S {
	int a;

	void foo() {
		a = -12;
	}
}

int main() {
	mixin("int b;");
	mixin("b") = mixin("42");

	assert(mixin("22 + 31") == 53);
	assert(mixin("22") * mixin("2") == mixin("44"));

	switch (mixin("b")) {
		case mixin("1"):
			return 12;

		case mixin("42"):
			break;

		default:
			assert(0);
	}

	S s;
	mixin("s").foo();
	int a = s.a;
	mixin("switch(a) { case -12: break; default: b = 23; break; }");

	uint ctr;
	foreach (c; mixin("\"test\"")) {
		ctr++;
	}

	assert(ctr == 4);
	mixin("return mixin(\"b\");");
}
