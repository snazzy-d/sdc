//T error: overload_set_ambiguous.d:12:10:
//T error: Cannot infer type from overloaded function symbol ov.
int ov(int x) {
	return x + 1;
}

int ov(string s) {
	return 0;
}

void test() {
	auto f = ov;
}
