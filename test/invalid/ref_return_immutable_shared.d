//T error: ref_return_immutable_shared.d:4:1:
//T error: Can't bind immutable(int) to ref shared(int).
ref shared(int) f(ref immutable(int) x) {
	return x;
}
