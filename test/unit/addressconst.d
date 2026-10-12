shared int gShared;
immutable int gImm = 7;
const shared int gConstShared = 3;

shared(int)* gPtr = &gShared;

unittest shared_enum_address {
	enum shared(int)* p = &gShared;
	assert(p is &gShared);
}

unittest shared_global_init {
	assert(gPtr is &gShared);
}

unittest immutable_enum_address {
	enum immutable(int)* p = &gImm;
	assert(p is &gImm);
	assert(*p == 7);
}

unittest const_shared_enum_address {
	// FIXME: This runs into improper folding when casting constants.
	// alias CS = const shared(int);
	// enum CS* p = &gConstShared;
	enum const(shared(int))* p = &gConstShared;
	assert(p is &gConstShared);
	assert(*p == 3);
}

unittest load_of_constant_address {
	assert(*&gImm == 7);
}
