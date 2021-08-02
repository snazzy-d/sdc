//T compiles:yes
//T has-passed:yes
//T retval:36
// Closure

int main() {
	int a = 10;
	int foo() {
		return --a;
	}

	return () {
		return a++;
	}() + {
		return a -= 2;
	}() + foo() + ((int b) => a + b)(1);
}
