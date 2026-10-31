//T error: cast_referred_class_pointer.d:7:1:
//T error: Can't cast B* to A*.
class A {}
class B : A {}

A* f(B* p) {
	return p;
}
