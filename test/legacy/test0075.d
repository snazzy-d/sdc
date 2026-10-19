//T compiles:yes
//T has-passed:yes
//T retval:0
//? desc:Test goto case multiple cases in case list.

int transmogrify(int input) {
	int output = 0;
	switch (input) {
		case 0, 1:
			if (input == 0)
				goto case;
			else
				output++;
			goto case;
		case 2:
			output += 5;
			goto case;
		case 3:
			output += 5;
			break;
		case 4, 5, 6:
			goto default;
		case 7:
		case 8:
			output += 20;
			break;
		default:
			return -1;
	}

	return output;
}

int main() {
	bool defaultRan = false;
	switch (0) {
		default:
			defaultRan = true;
			break;
		case 0:
			goto default;
	}

	assert(defaultRan);

	assert(transmogrify(0) == 10);
	assert(transmogrify(1) == 11);

	assert(transmogrify(2) == 10);
	assert(transmogrify(3) == 5);
	assert(transmogrify(7) == 20);
	assert(transmogrify(8) == 20);

	assert(transmogrify(4) == -1);
	assert(transmogrify(5) == -1);
	assert(transmogrify(6) == -1);
	assert(transmogrify(128) == -1);
	return 0;
}
