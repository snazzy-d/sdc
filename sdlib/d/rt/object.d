module d.rt.object;

extern(C):

Object __sd_class_downcast(Object o, ClassInfo c) {
	auto t = getTypeid(o);

	if (t is c) {
		return o;
	}

	while (t !is t.base) {
		// Promote
		t = t.base;

		if (t is c) {
			return o;
		}
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
	alias ClassInfo = ClassInfoImpl * ;

	struct ClassInfoImpl {
		void* vtbl;
		ClassInfo base;
	}

	ClassInfo getTypeid(Object o) {
		auto vtbl = *(cast(void**) o);
		return cast(ClassInfo) (vtbl - ClassInfoImpl.sizeof);
	}
}
