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

unittest explicit_qualifier_casts {
	// An explicit cast can change qualifiers in any way, and the
	// result refers to the same data.
	int i = 1;
	const(int) ci = 2;
	shared(int) si = 3;
	assert(cast(void*) &cast(int) ci is cast(void*) &ci);
	assert(cast(void*) &cast(shared(int)) i is cast(void*) &i);
	assert(cast(void*) &cast(int) si is cast(void*) &si);

	int* p = &i;
	const(int)* cp = &ci;
	immutable(int)* ip = null;
	shared(int)* sp = &si;
	const(shared(int))* csp = sp;
	assert(cast(void*) &cast(int*) cp is cast(void*) &cp);
	assert(cast(void*) &cast(int*) ip is cast(void*) &ip);
	assert(cast(void*) &cast(int*) sp is cast(void*) &sp);
	assert(cast(void*) &cast(immutable(int)*) p is cast(void*) &p);
	assert(cast(void*) &cast(immutable(int)*) cp is cast(void*) &cp);
	assert(cast(void*) &cast(shared(int)*) p is cast(void*) &p);
	assert(cast(void*) &cast(shared(int)*) csp is cast(void*) &csp);
	assert(cast(void*) &cast(int*) cast(shared(int*)) sp is cast(void*) &sp);

	int** pp = &p;
	const(int)** cpp = &cp;
	immutable(int)** ipp = &ip;
	shared(int)** spp = &sp;
	assert(cast(void*) &cast(const(int)**) pp is cast(void*) &pp);
	assert(cast(void*) &cast(int**) cpp is cast(void*) &cpp);
	assert(cast(void*) &cast(const(int)**) ipp is cast(void*) &ipp);
	assert(cast(void*) &cast(const(shared(int))**) spp is cast(void*) &spp);

	int[] s = [1, 2];
	const(int)[] cs = s;
	int[][] ss = [s];
	int*[] ps = [p];
	assert(cast(void*) &cast(int[]) cs is cast(void*) &cs);
	assert(cast(void*) &cast(immutable(int)[]) s is cast(void*) &s);
	assert(cast(void*) &cast(const(int)[][]) ss is cast(void*) &ss);
	assert(cast(void*) &cast(const(int)*[]) ps is cast(void*) &ps);

	int[2] a = [1, 2];
	const(int)[2]* cpa = &a;
	const(int)*[2] cpa1 = [cp, cp];
	assert(cast(void*) &cast(int[2]*) cpa is cast(void*) &cpa);
	assert(cast(void*) &cast(int*[2]) cpa1 is cast(void*) &cpa1);

	// FIXME: The qualifier of the elements is not changed.
	// const(int*)[2] cpa2 = [p, p];
	// assert(cast(void*) &cast(int*[2]) cpa2 is cast(void*) &cpa2);
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

unittest implicit_qualifier_conversions {
	// A value is copied, so its own qualifier can change freely.
	int i = 1;
	const(int) ci = i;
	immutable(int) ii = ci;
	shared(int) si = ii;
	int fromShared = si;
	assert(fromShared == 1);

	// What a pointer refers to can only become const.
	int* p = &i;
	const(int)* cp = p;
	immutable(int)* ip = &ii;
	const(int)* cip = ip;
	assert(*cp == 1 && *cip == 1);

	int[] s = [1, 2];
	const(int)[] cs = s;
	assert(cs[1] == 2);

	// Deeper levels can change if all the levels above are const.
	int** pp = &p;
	const(int*)* cpp = pp;
	const(int**) cppp = pp;
	assert(**cpp == 1 && **cppp == 1);

	int*[] ps = [p];
	const(int*)[] cps = ps;
	assert(*cps[0] == 1);

	int[][] ss = [s];
	const(int[])[] css = ss;
	assert(css[0][1] == 2);

	// Nothing can be written through cppx, so it can refer to immutable
	// and mutable data alike. Rebinding it does not change what it
	// referred to.
	immutable(int)** ppi = &ip;
	const(int*)* cppi = ppi;
	assert(*cppi is &ii);

	cppi = pp;
	assert(ip is &ii);
	assert(*cppi is &i);

	// The elements of a static array are copied with it.
	int*[2] pa2 = [p, p];
	const(int)*[2] cpa2 = pa2;
	assert(*cpa2[0] == 1);

	// Through a pointer, they can only become const.
	int[2] a = [1, 2];
	int[2]* pa = &a;
	const(int)[2]* cpa = pa;
	assert((*cpa)[1] == 2);

	shared(int)[2] sa = [1, 2];
	shared(int)[2]* psa = &sa;
	const(shared(int[2]))* cpsa = psa;
	assert((*cpsa)[1] == 2);

	// FIXME: The qualifier of the pointers is not looked through.
	// const(int*)[2] cpa5 = pa2;
	// const(int)*[2] cpa6 = cpa5;
	// assert(*cpa6[0] == 1);

	// Shared and immutable data can both be referred to as const shared.
	shared(int)* sp = &si;
	const(shared(int))* csp = sp;
	const(shared(int))* csip = ip;
	assert(*csp == 1 && *csip == 1);

	shared(int)** spp = &sp;
	const(shared(int)*)* cspp = spp;
	assert(**cspp == 1);
}
