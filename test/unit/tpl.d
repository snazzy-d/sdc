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

struct Array(T, uint N) {
	T[N] elements;
}

struct S(uint N) {
	uint data = N;

	auto getN()() {
		return data;
	}

	auto sum(uint K)(S!K other) {
		return getN() + other.getN();
	}

	auto set(T)(ref Array!(T, N) a, uint i, uint v) {
		a.elements[i] = v;
	}

	auto get(T)(ref const Array!(T, N) a, uint i) {
		return a.elements[i];
	}
}

unittest patterns {
	S!7 s;
	assert(s.getN() == 7);

	S!12 k;
	assert(k.sum!7(s) == 19);
	assert(s.sum!12(k) == 19);

	Array!(uint, 7) a;
	s.set(a, 3, 42);
	assert(a.elements[3] == 42);
	assert(s.get(a, 3) == 42);
}
