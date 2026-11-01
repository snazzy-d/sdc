//T error: cast_array_class_down.d:7:8:
//T error: Can't cast A[2] to B[2].
class A {}
class B : A {}

B[2] f(A[2] x) {
	return cast(B[2]) x;
}
