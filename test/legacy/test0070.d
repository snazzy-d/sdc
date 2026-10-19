//T compiles:yes
//T has-passed:yes
//T retval:0
//? desc:Test the do-while loop.

int main() {
	int i = 0;
	do {
		i++;
	} while (i > 10); // Should run once.

	assert(i == 1);

	do
		i--;
	while (i > -10);

	assert(i == -10);

	// Break.
	i = 0;
	do {
		i++;
		if (i == 5)
			break;
	} while (i < 10);

	assert(i == 5);

	// Continue.
	i = 0;
	int j = 0;
	do {
		i++;
		if (i > 5)
			continue;
		j++;
	} while (i < 10);

	assert(j == 5);

	return 0;
}
