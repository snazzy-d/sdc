//T compiles:yes
//T retval:0
//T has-passed:yes
// Tests strings and character literals, and string/pointer casts.

extern(C) size_t strlen(const char* s);

int main() {
	string str = "test";
	if (str.length != 4) {
		return 1;
	}

	if (str[2] != 's') {
		return 2;
	}

	const(char)* p = "test";
	if (strlen(p) == str.length + 1) {
		return 3;
	}

	return 0;
}
