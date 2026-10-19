//T compiles:yes
//T has-passed:yes
//T retval:42

int foo(char* p) {
	if (*p == '\0') {
		return 0;
	}

	switch (*p) {
		case 'i':
			p++;
			if (*p == '\0') {
				return 1;
			}

			switch (*p) {
				case 'f':
					return 2;

				case 's':
					return 3;

				default:
					return 42;
			}

		default:
			return 1;
	}
}

int main() {
	char[3] str;
	str[0] = 'i';
	str[1] = 'g';
	str[2] = '\0';

	return foo(&str[0]);
}
