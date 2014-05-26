module util.fastcast;

U fastCast(U, T)(T t) if(is(T == class) && is(U == class) && is(U : T)) in {
	assert(cast(U) t);
} body {
	return *(cast(U*) &t);
}

