uint sum(uint A, uint B)() {
	return A + B;
}

unittest sum {
	assert(sum!(31, 72)() == 103);
}
