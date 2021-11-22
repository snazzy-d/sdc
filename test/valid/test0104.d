//T compiles:yes
//T has-passed:yes
//T retval:42
// Test creation of delegates from member function.

struct S {
	int i;
	T t;

	auto add(int a) {
		t.i = a + i;
		return t.add;
	}
}

struct T {
	int i;
	int add(int a) {
		return i + a;
	}
}

int main() {
	S s;
	s.i = s.t.i = 1;
	auto dg1 = s.add;
	auto dg2 = dg1(34);
	return dg2(7);
}
