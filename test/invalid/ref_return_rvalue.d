//T error: ref_return_rvalue.d:8:1:
//T error: Can't bind a value without an address to ref int.
int make() {
	return 3;
}

ref int get() {
	return make();
}

int main() {
	return get();
}
