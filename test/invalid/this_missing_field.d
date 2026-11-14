//T error: this_missing_field.d:8:9:
//T error: Cannot find a suitable this pointer.

struct S {
	int x;

	static int foo() {
		return x;
	}
}
