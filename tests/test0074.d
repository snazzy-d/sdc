//T compiles:yes
//T has-passed:yes
//T retval:0
//? desc:Test a basic switch.

int transmogrify(int input) {
	int output;
	switch (input) {
		default:
			output = 0;
			return output;
		case 1:
			output = 10;
			break;
		case 2:
			output = 20;
			break;
		case 3:
			output = 0;
			while(true) {
				++output;
				if (output == 30)
					break;
			}
			break;
	}
	return output;
}

int main() {
	bool didRun = false;
	switch(0) {
		// didRun = true;
		default:
	}
	assert(!didRun);
	
	switch(0) { // Should not cause any warnings.
		case 0:
			didRun = true;
			break;
		default:
			break;
	}
	
	assert(didRun);
	
	assert(transmogrify(1) == 10);
	assert(transmogrify(2) == 20);
	assert(transmogrify(3) == 30);
	assert(transmogrify(4) == 0);
	return transmogrify(128);
}
