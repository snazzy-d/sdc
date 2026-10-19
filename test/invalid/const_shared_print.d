//T error: const_shared_print.d:4:1:
//T error: Can't cast shared(const(int))* to int.
int f(const(shared(int))* x) {
	return x;
}
