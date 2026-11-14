//T error: this_missing_method.d:10:2:
//T error: Cannot find a suitable this pointer.

struct S {
	int x;

	void bar() {}

	static void foo() {
		bar();
	}
}
