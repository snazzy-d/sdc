class A {}

class B : A {}

final class C : B {}

unittest base {
	assert(typeid(A).base is typeid(Object));
	assert(typeid(B).base is typeid(A));
	assert(typeid(C).base is typeid(B));
}

unittest downcast {
	Object n = null;
	auto na = cast(A) n;
	auto nb = cast(B) n;
	auto nc = cast(C) n;

	assert(na is null);
	assert(nb is null);
	assert(nc is null);

	Object a = new A();
	auto aa = cast(A) a;
	auto ab = cast(B) a;
	auto ac = cast(C) a;

	assert(aa is a);
	assert(ab is null);
	assert(ac is null);

	Object b = new B();
	auto ba = cast(A) b;
	auto bb = cast(B) b;
	auto bc = cast(C) b;

	assert(ba is b);
	assert(bb is b);
	assert(bc is null);

	Object c = new C();
	auto ca = cast(A) c;
	auto cb = cast(B) c;
	auto cc = cast(C) c;

	assert(ca is c);
	assert(cb is c);
	assert(cc is c);
}
