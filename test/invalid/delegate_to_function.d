//T error: delegate_to_function.d:13:1:
//T error: Can't cast int delegate() <{ref S}> to int function().
class A {}
class B : A {}

struct S {
	int get() {
		return 0;
	}
}

int function() g(ref S s) {
	return s.get;
}
