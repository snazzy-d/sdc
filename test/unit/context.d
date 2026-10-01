unittest context_read {
	int x = 7;
	int get() {
		return x;
	}

	assert(get() == 7);
}

unittest context_mutate {
	int x = 1;
	void inc() {
		x = x + 1;
	}

	inc();
	assert(x == 2);
}

unittest context_nested {
	int x = 4;
	int outer() {
		int inner() {
			return x;
		}

		return inner();
	}

	assert(outer() == 4);
}

unittest context_two_locals {
	int a = 1;
	int b = 2;
	int sum() {
		return a + b;
	}

	assert(sum() == 3);
	a = 5;
	assert(sum() == 7);
}
