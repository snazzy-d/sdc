//T error: overload_set_no_match.d:12:20:
//T error: No match found
int ov(int x) {
	return x + 1;
}

int ov(string s) {
	return 0;
}

void test() {
	int function(long) f = ov;
}
