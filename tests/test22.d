//T compiles:yes
//T retval:33
//T has-passed:yes
//T dependency:test22_import.d

import test22_import;

int begin() {
	return 1 + tenptr()() + addOne(&twelve) + 8;
}

int twelve() {
	return 12;
}

int main() {
	return start();
}

