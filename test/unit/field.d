struct S {
	int x;
	int y;
}

class C {
	int x;
}

unittest field_lvalue {
	S s;
	s.x = 1;
	s.y = 2;
	assert(s.x == 1);
	assert(s.y == 2);

	int* p = &s.y;
	assert(p is &s.y);
	*p = 9;
	assert(s.y == 9);
	assert(*&s.x == 1);
}

unittest field_class {
	C c = new C();
	c.x = 5;
	assert(c.x == 5);
}

unittest field_slice {
	int[2] a;
	a[0] = 1;
	a[1] = 2;
	int[] s = a[0 .. a.length];
	assert(s.length == 2);
	assert(s.ptr is &a[0]);
}

S pair() {
	S s;
	s.x = 3;
	s.y = 4;
	return s;
}

unittest extract_rvalue_field {
	assert(pair().x == 3);
	assert(pair().y == 4);
}

struct Statics {
	static int g;
	static int[2] a;
}

uint staticsEvaluations;

Statics statics() {
	staticsEvaluations++;

	Statics s;
	return s;
}

void increment(ref int i) {
	i++;
}

ref int staticRef() {
	return statics().g;
}

unittest field_static_through_instance {
	// A static member reached through an instance is the static member, and
	// the instance is evaluated.
	statics().g = 1;
	assert(Statics.g == 1);
	assert(staticsEvaluations == 1);

	assert(statics().g == 1);
	assert(staticsEvaluations == 2);

	int* p = &statics().g;
	assert(p is &Statics.g);
	assert(staticsEvaluations == 3);

	*p = 2;
	assert(Statics.g == 2);

	statics().g++;
	assert(Statics.g == 3);
	assert(staticsEvaluations == 4);

	statics().g += 2;
	assert(Statics.g == 5);
	assert(staticsEvaluations == 5);

	increment(statics().g);
	assert(Statics.g == 6);
	assert(staticsEvaluations == 6);

	staticRef()++;
	assert(Statics.g == 7);
	assert(staticsEvaluations == 7);

	statics().a[1] = 5;
	assert(Statics.a[1] == 5);
	assert(staticsEvaluations == 8);

	assert(statics().a.ptr is &Statics.a[0]);
	assert(staticsEvaluations == 9);

	foreach (ref i; statics().a) {
		i++;
	}

	assert(Statics.a[0] == 1);
	assert(Statics.a[1] == 6);
	assert(staticsEvaluations == 10);
}
