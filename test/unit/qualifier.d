struct Small {
	int a;

	this(int a) {
		this.a = a;
	}
}

bool isShared(Small s) {
	return false;
}

bool isShared(shared(Small) s) {
	return true;
}

struct Large {
	long a;
	long b;
	long c;
	long d;
	long e;

	this(long a) {
		this.a = a;
	}
}

bool isShared(Large l) {
	return false;
}

bool isShared(shared(Large) l) {
	return true;
}

unittest struct_construction {
	// A struct is constructed with the qualifier of its type.
	assert(!isShared(Small(1)));
	assert(isShared(shared(Small)(1)));

	assert(!isShared(Large(1)));
	assert(isShared(shared(Large)(1)));
}
