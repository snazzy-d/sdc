//T compiles:yes
//T has-passed:yes
//T retval:45
// Varrious array operations.

uint[4] arr;

auto foo() {
	return arr.ptr;
}

auto bar() {
	return arr;
}

int main() {
	arr[0] = 25;
	arr[1] = 10;

	return foo()[1] + bar()[1] + *foo();
}
