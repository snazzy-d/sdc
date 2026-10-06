//T error: this_not_consumed_typepos.d:10:10:
//T error: S() has not been consumed.

struct S {
	struct Nested {
		int x;
	}
}

alias T = S.init.Nested;

int main() {
	T t;
	return 0;
}
