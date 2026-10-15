//T error: overload_set_return_no_match.d:12:1:
//T error: No match found
int ov(int x) {
	return x + 1;
}

int ov(string s) {
	return 0;
}

int function(long) pick() {
	return ov;
}
