//T compiles:yes
//T has-passed:yes
//T retval:0
// downcast

class A {}

class B : A {}

final class C : B {}

void main() {
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
