module util.fastcast;

U fastCast(U, T)(T t) if (is(T == class) && is(U == class) && is(U : T)) in {
	assert(cast(U) t);
} do {
	return *(cast(U*) &t);
}

// TODO: Check that T is an enum member.
U fastCast(U, T)(T t) if (is(U == union)) {
	return *(cast(U*) &t);
}
