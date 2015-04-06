module d.rt.object;

extern(C):

Object __sd_class_downcast(Object o, ClassInfo c) {
	auto t = typeid(o);
	
	if(t is c) {
		return o;
	}
	
	while(t !is t.base) {
		// Promote
		t = t.base;
		
		if(t is c) {
			return o;
		}
	}
	
	return null;
}

