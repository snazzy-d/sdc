//T compiles:yes
//T has-passed:no
//T retval:0
//? desc:Test case range statements.

int transmogrify(int input) {
	switch (input) {
		case 0:
			return 1;
		case 1: .. case 10:
			return 2;
		case 11:
			return 3;
		case 12: .. case 12:
			return 4;
		case 13:
			return 5;
		default:
			return 0;
	}
}

void main() {
	assert(transmogrify(0) == 1);

	foreach (i; 1 .. 11)
		assert(transmogrify(i) == 2);

	assert(transmogrify(11) == 3);
	assert(transmogrify(12) == 4);
	assert(transmogrify(13) == 5);

	assert(transmogrify(14) == 0);
	assert(transmogrify(15) == 0);
}
