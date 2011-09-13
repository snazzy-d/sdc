//T compiles:yes
//T retval:0
//? desc:Test a basic switch.

int transmogrify(int input)
{
	int output;
	switch (input) {
		case 1:
			return 10;
		case 2:
			return 20;
		default:
			output = 0;
    }
	return output;
}

int main()
{
    assert(transmogrify(1) == 10);
	assert(transmogrify(2) == 20);
	assert(transmogrify(3) == 0);
	return transmogrify(128);
}