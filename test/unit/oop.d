class A {}

class B : A {}

final class C : B {}

unittest base {
	assert(typeid(A).base is typeid(Object));
	assert(typeid(B).base is typeid(A));
	assert(typeid(C).base is typeid(B));
}
