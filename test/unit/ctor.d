struct Small {
	int a;
	int b;

	this(int a) {
		this(a, 2);
	}

	this(int a, int b) {
		this.a = a;
		this.b = b;
	}
}

unittest forward_small_struct {
	auto s = Small(1);
	assert(s.a == 1);
	assert(s.b == 2);
}

struct Large {
	long a;
	long b;
	long c;
	long d;
	long e;

	this(long a) {
		this(a, 2);
	}

	this(long a, long b) {
		this.a = a;
		this.b = b;
		e = 5;
	}
}

unittest forward_large_struct {
	auto l = Large(1);
	assert(l.a == 1);
	assert(l.b == 2);
	assert(l.c == 0);
	assert(l.e == 5);
}

class Class {
	int a;
	int b;

	this(int a) {
		this(a, 2);
	}

	this(int a, int b) {
		this.a = a;
		this.b = b;
	}
}

unittest forward_class {
	auto c = new Class(1);
	assert(c.a == 1);
	assert(c.b == 2);
}
