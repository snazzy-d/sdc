//T error: this_not_consumed_template.d:12:1:
//T error: Cannot use an expression to access Foo.

struct S {
	template Foo(T) {
		alias Foo = T;
	}
}

void main() {
	S s;
	s.Foo;
}
