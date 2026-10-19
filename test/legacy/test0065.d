//T compiles:yes
//T has-passed:yes
//T retval:0
//? desc:Test range foreach.

int main() {
	int i = 0;
	foreach (j; 1 .. 5) {
		i += j;
	}

	assert(i == 10);
	foreach_reverse (j; 1 .. 5) {
		i -= j;
	}

	assert(i == 0);

	string str = "foobar";
	string str2 = "raboof";

	foreach (size_t j; 0 .. str.length) {
		assert(str[j] == str2[(str2.length - j) - 1]);
	}

	int k = 0;
	foreach_reverse (size_t j; 0 .. str.length) {
		assert(str2[j] == str[k++]);
	}

	foreach (char* it; str.ptr .. str.ptr + str.length) {
		assert(*it == str[i]);
		i++;
	}

	// Break.

	i = 0;
	foreach (j; 0 .. 10) {
		if (j == 5)
			break;

		i++;
	}

	assert(i == 5);

	// Continue.
	i = 0;
	foreach (j; 0 .. 10) {
		if (j < 5)
			continue;

		i++;
	}

	assert(i == 5);

	return 0;
}
