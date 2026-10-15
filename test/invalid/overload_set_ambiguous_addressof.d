//T error: core.exception.AssertError@src/d/common/builtintype.d(202): Use SizeofVisitor for None
int ov(int x) {
	return x + 1;
}

int ov(string s) {
	return 0;
}

void test() {
	auto f = &ov;
}
