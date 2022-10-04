module d.rt.object;

version(SDC) {} else {
	// We need to do some dirty manipulation when not
	// using SDC as expected layout differs.
	alias ClassInfo = ClassInfoImpl*;

	struct ClassInfoImpl {
		void* vtbl;
		ClassInfo[] primaries;
	}
}

Object __sd_class_downcast()(Object o, ClassInfo c) {
	version(SDC) {
		auto t = typeid(o);
	} else {
		auto t = cast(ClassInfo) *(cast(void**) o);
	}

	auto cDepth = c.primaries.length - 1;

	if (t.primaries.length <= cDepth) {
		return null;
	}

	if (t.primaries[cDepth] is c) {
		return o;
	}

	return null;
}
