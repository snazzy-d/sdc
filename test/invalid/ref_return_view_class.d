//T error: ref_return_view_class.d:7:1:
//T error: Can't bind B to ref A.
class A {}
class B : A {}

ref A f(ref B x) {
	return x;
}
