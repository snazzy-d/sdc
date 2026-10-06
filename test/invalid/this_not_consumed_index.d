//T error: this_not_consumed_index.d:10:1:
//T error: *&&a[cast(ulong) 0] has not been consumed.

struct S {
	int x;
}

void main() {
	S[1] a;
	a[0].nope;
}
