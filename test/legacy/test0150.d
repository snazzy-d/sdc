//T compiles:yes
//T has-passed:yes
//T retval:6
// Catch

auto a = 5;

void foo() {
	scope(exit) a++;
	throw new Exception();
}

int main() {
	try {
		foo();
	} catch (Exception e) {
		return a;
	}

	return 0;
}
