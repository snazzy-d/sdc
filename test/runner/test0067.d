//T compiles:yes
//T has-passed:yes
//T retval:0

int main() {
	string str = "foobar";
	string str2 = "raboof";

	int count = 0;
	for (int i = 0; i < 10; i++)
		count++;

	assert(count == 10);

	ptrdiff_t i = str.length - 1;
	ptrdiff_t j = 0;
	for (; i > -1; i--) {
		assert(str[i] == str2[j]);
		j++;
	}

	// Break.

	i = 0;
	for (;;) {
		if (i == 10)
			break;
		else
			++i;
	}

	assert(i == 10);

	// Continue.
	i = 0;
	j = 0;
	for (i = 0; i < 10; i++) {
		if (i > 5)
			continue;
		++j;
	}

	assert(i == 10);
	assert(j == 6);
	return 0;
}
