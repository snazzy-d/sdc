uint sum(uint A, uint B)() {
	return A + B;
}

unittest sum {
	assert(sum!(31, 72)() == 103);
}

uint rec(uint N)() {
	return N < 8 ? N : rec!(N / 2)();
}

unittest rec {
	assert(rec!25() == 6);
}

struct S(uint N) {
	uint data = N;

	auto getN() {
		return data;
	}

	auto sum(uint K)(S!K other) {
		return getN() + other.getN();
	}
}

unittest S {
	S!7 s;
	assert(s.getN() == 7);

	S!12 k;
	assert(k.sum!7(s) == 19);
	assert(s.sum!12(k) == 19);
}
