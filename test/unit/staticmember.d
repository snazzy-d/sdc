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

unittest reached_through_instance {
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
