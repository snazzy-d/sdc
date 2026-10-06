//T error: this_not_consumed_typepos.d:10:10:
//T error: Nested can't be resolved in type __none__.

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
