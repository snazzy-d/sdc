//T error: ref_return_rvalue_const.d:8:1:
//T error: Can't bind a value without an address to ref const(int).
int make() {
	return 3;
}

ref const(int) get() {
	return make();
}

int main() {
	return get();
}
