int add(int a, int b) {
	return a + b;
}

unittest add {
	int function(int, int) f0 = add;
	assert(f0(25, 12) == 37);

	int function(int, int) f1 = &add;
	assert(f1(30, 2) == 32);
}

unittest constant {
	static int result = 0;

	static void set(int x) {
		result = x;
	}

	set(3);
	assert(result == 3);

	static void function(int) cstfun0 = set;
	cstfun0(5);
	assert(result == 5);

	static shared void function(int) cstfun1 = set;
	cstfun1(7);
	assert(result == 7);
}

class Base {}
class Derived : Base {}

Derived makeDerived() {
	return new Derived();
}

int* makePointer() {
	static int i = 3;
	return &i;
}

int readBase(Base b) {
	return b is null ? 0 : 1;
}

int readConst(const(int)* p) {
	return *p;
}

int readUint(uint u) {
	return cast(int) u;
}

unittest function_conversions {
	// What a function returns can be seen as anything it converts to.
	Base function() makeBase = makeDerived;
	assert(cast(Derived) makeBase() !is null);

	const(int)* function() makeConst = makePointer;
	assert(*makeConst() == 3);

	// What a function is given can be anything that converts to it.
	int function(Derived) readDerived = readBase;
	assert(readDerived(new Derived()) == 1);

	int i = 5;
	int function(int*) readMutable = readConst;
	assert(readMutable(&i) == 5);

	// A value with the same representation converts to and from int.
	int function(int) readInt = readUint;
	assert(readInt(-1) == -1);

	// A function can be seen as a pointer to anything.
	void* p = &makePointer;
	assert(p is cast(void*) &makePointer);
}
