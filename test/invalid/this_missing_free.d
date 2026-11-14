//T error: this_missing_free.d:5:8:
//T error: Cannot find a suitable this pointer.

int foo() {
	return this.x;
}
