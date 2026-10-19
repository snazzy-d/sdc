//T compiles:yes
//T has-passed:yes
//T retval:9
// Catch

auto a = 7;

void foo() {
	try {
		throw new Exception();
	} catch (Exception e) {
		a += 2;
		throw new Exception();
	}
}

int main() {
	try {
		foo();
	} catch (Exception e) {
		return a;
	}

	return 0;
}
