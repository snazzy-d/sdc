module d.rt.object;

extern(C):

Object __sd_class_downcast(Object o, ClassInfo c) {
	auto t = getTypeid(o);

	auto oDepth = t.primaries.length - 1;
	auto cDepth = c.primaries.length - 1;

	if (oDepth < cDepth) {
		return null;
	}

	if (t.primaries[cDepth] is c) {
		return o;
	}

	return null;
}

extern(D):

version (SDC) {
	ClassInfo getTypeid(Object o) {
		return typeid(o);
	}
} else {
	// We need to do some dirty manipulation when not
	// using SDC as expected layout differs.
	alias ClassInfo = ClassInfoImpl*;

	struct ClassInfoImpl {
		void* vtbl;
		ClassInfo[] primaries;
	}

	ClassInfo getTypeid(Object o) {
		return cast(ClassInfo) *(cast(void**) o);
	}
}
