unittest voiddg {
	uint a = 0;
	void increment() {
		a++;
	}

	increment();
	assert(a == 1);

	void forward(void delegate() dg) {
		return dg();
	}

	forward(increment);
	assert(a == 2);
}
