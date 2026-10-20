shared int gShared;
immutable int gImm = 7;
const shared int gConstShared = 3;

shared(int)* gPtr = &gShared;

// The address of a global cast to another type is a constant.
const(int)* gConstPtr = &gImm;
const(shared(int))* gConstSharedPtr = &gShared;
void* gVoidPtr = cast(void*) &gImm;
const(char)[] gConstString = "abc";

// So is an integer cast to a pointer.
enum void* NullPtr = cast(void*) 0;
enum void* MaxPtr = cast(void*) size_t.max;

unittest shared_enum_address {
	enum shared(int)* p = &gShared;
	assert(p is &gShared);
}

unittest shared_global_init {
	assert(gPtr is &gShared);
}

unittest cast_global_init {
	assert(gConstPtr is &gImm);
	assert(gConstSharedPtr is &gShared);
	assert(gVoidPtr is cast(void*) &gImm);
	assert(gConstString.length == 3 && gConstString[1] == 'b');

	assert(NullPtr is null);
	assert(cast(size_t) MaxPtr == size_t.max);
}

unittest immutable_enum_address {
	enum immutable(int)* p = &gImm;
	assert(p is &gImm);
	assert(*p == 7);
}

unittest const_shared_enum_address {
	enum const(shared(int))* p = &gConstShared;
	assert(p is &gConstShared);
	assert(*p == 3);
}

unittest const_shared_alias_address {
	alias CS = const shared(int);
	enum CS* p = &gConstShared;
	assert(*p == 3);
}

unittest load_of_constant_address {
	assert(*&gImm == 7);
}
