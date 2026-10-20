//T error: enum_value_template_arg.d:10:1:
//T error: No match
enum Kind {
	A,
}

void pick(Kind K)() {}

void f() {
	pick!(0)();
}
