unittest address_of_cast {
	int x = 2;

	{
		// Exact cast.
		auto p = &cast(int) x;
		assert(*p == 2);
	}

	{
		// Qual cast.
		auto p = &cast(const(int)) x;
		assert(*p == 2);
	}
}

unittest static_array_qualifier {
	// The elements are copied with the array.
	int[2] a = [1, 2];
	const(int)[2] ca = a;
	int[2] fromConst = ca;
	assert(fromConst[1] == 2);

	// The qualifier of a static array is the qualifier of its elements.
	const(int[2])* cpa = &a;
	const(int)[2]* cpa2 = cpa;
	assert((*cpa2)[1] == 2);

	const(int)[2]* cpa3 = &a;
	const(int[2])* cpa4 = cpa3;
	assert((*cpa4)[0] == 1);
}
