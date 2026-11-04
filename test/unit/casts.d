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
	// The result of an explicit cast refers to the same data if nothing can
	// be written through it that is not valid for the original.
	int i = 1;
	shared(int) si = 2;
	assert(cast(void*) &cast(const(int)) i is cast(void*) &i);
	assert(cast(void*) &cast(const(shared(int))) si is cast(void*) &si);

	int* p = &i;
	int** pp = &p;
	int[] s = [1, 2];
	int[2] a = [1, 2];
	assert(cast(void*) &cast(const(int*)) p is cast(void*) &p);
	assert(cast(void*) &cast(const(int**)) pp is cast(void*) &pp);
	assert(cast(void*) &cast(const(int[])) s is cast(void*) &s);
	assert(cast(void*) &cast(const(int)[2]) a is cast(void*) &a);
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

	const(int*)[2] cpa5 = pa2;
	const(int)*[2] cpa6 = cpa5;
	assert(*cpa6[0] == 1);

	// Shared and immutable data can both be referred to as const shared.
	shared(int)* sp = &si;
	const(shared(int))* csp = sp;
	const(shared(int))* csip = ip;
	assert(*csp == 1 && *csip == 1);

	shared(int)** spp = &sp;
	const(shared(int)*)* cspp = spp;
	assert(**cspp == 1);
}

unittest void_pointer_conversions {
	// Nothing is written as void, so anything can be referred to as void, as
	// long as the qualifier converts.
	int i = 1;
	const(int) ci = 2;
	immutable(int) ii = 3;
	shared(int) si = 4;

	void* p = &i;
	const(void)* cp = &ci;
	const(void)* cpi = &ii;
	immutable(void)* ip = &ii;
	shared(void)* sp = &si;
	const(shared(void))* csp = &si;
	const(shared(void))* csip = &ii;
	assert(p is cast(void*) &i);
	assert(cp is cast(void*) &ci);
	assert(cpi is cast(void*) &ii);
	assert(ip is cast(immutable(void)*) &ii);
	assert(sp is cast(shared(void)*) &si);
	assert(csp is cast(const(shared(void))*) &si);
	assert(csip is cast(const(shared(void))*) &ii);

	// What is pointed to can be anything, including a pointer.
	int* pi = &i;
	void* ppi = &pi;
	assert(ppi is cast(void*) &pi);
}

class Base {}
class Derived : Base {}

unittest referred_type_conversions {
	// What a reference refers to can be seen as another type with the same
	// representation, as long as nothing is written through it.
	auto d = new Derived();
	Derived* pd = &d;
	const(Base)* cpb = pd;
	assert(*cpb is d);

	Derived[] ds = [d];
	const(Base)[] cbs = ds;
	assert(cbs[0] is d);

	int i = -1;
	int* pi = &i;
	const(uint)* cpu = pi;
	assert(*cpu == uint.max);

	int[] s = [-1];
	const(uint)[] cus = s;
	assert(cus[0] == uint.max);

	immutable(int) ii = -1;
	immutable(uint)* ipu = &ii;
	assert(*ipu == uint.max);

	int** ppi = &pi;
	const(void*)* cppv = ppi;
	assert(cast(void*) cppv is cast(void*) &pi);

	int*[] pis = [pi];
	const(void*)[] cpvs = pis;
	assert(cpvs[0] is cast(void*) pi);
}

int readConstUint(ref const(uint) x) {
	return cast(int) x;
}

Base readConstBase(ref const(Base) b) {
	return cast(Base) b;
}

unittest referred_parameter_conversions {
	// A function taking a ref parameter can be seen as one taking a ref to
	// another type with the same representation, as long as nothing is
	// written through it.
	int function(ref int) readInt = &readConstUint;
	int i = -1;
	assert(readInt(i) == -1);

	Base function(ref Derived) readDerived = &readConstBase;
	auto d = new Derived();
	assert(readDerived(d) is d);
}

class ArrayBase {}
class ArrayDerived : ArrayBase {}

unittest static_array_casts {
	// The elements are stored in the array, so it can be cast to an array of
	// elements with the same representation.
	int[2] a = [-1, 2];
	uint[2] u = cast(uint[2]) a;
	assert(u[0] == uint.max && u[1] == 2);

	int[2][2] n = [[-1, 1], [2, 3]];
	uint[2][2] un = cast(uint[2][2]) n;
	assert(un[0][0] == uint.max && un[1][1] == 3);

	const(int)[2] ca = a;
	int[2] ma = cast(int[2]) ca;
	assert(ma[1] == 2);

	auto d = new ArrayDerived();
	ArrayDerived[2] ds = [d, d];
	ArrayBase[2] bs = cast(ArrayBase[2]) ds;
	assert(bs[0] is d);
}
