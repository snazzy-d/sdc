//T error: cast_referred_class_pointer_unconst.d:7:1:
//T error: Can't cast const(B)* to A*.
class A {}
class B : A {}

A* f(const(B)* p) {
	return p;
}
