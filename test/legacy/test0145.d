//T compiles:yes
//T has-passed:yes
//T retval:0
// typeid.

class A {}

class B : A {}

void main() {
	Object a = new A();
	Object b = new B();

	assert(typeid(a) !is typeid(b));
	assert(typeid(typeof(a)) is typeid(typeof(b)));
	assert(typeid(a) !is typeid(typeof(b)));
	assert(typeid(typeof(a)) !is typeid(b));

	b = new A();

	assert(a !is b);
	assert(typeid(a) is typeid(b));
}
