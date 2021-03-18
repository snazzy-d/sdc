//T compiles:yes
//T has-passed:yes
//T retval:0
// downcast

class A {}
class B : A {}

void main() {
	Object a = new A();
	Object b = new B();

	auto a1 = cast(A) a;
	auto a2 = cast(B) a;

	assert(a1 is a);
	assert(a2 is null);

	auto b1 = cast(A) b;
	auto b2 = cast(B) b;

	assert(b1 is b);
	assert(b2 is b);
}
