//T error: slice_struct.d:10:10:
//T error: Can't slice S.

struct S {
	int x;
}

int main() {
	S s;
	auto t = s[0 .. 1];
	return 0;
}
