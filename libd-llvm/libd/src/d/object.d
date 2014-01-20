module d.object;

import d.ir.symbol;

import d.context;

final class ObjectReference {
	private Module object;
	
	this(Module object) {
		this.object = object;
	}
	
	auto getObject() {
		return cast(Class) object.dscope.resolve(BuiltinName!"Object");
	}
	
	auto getTypeInfo() {
		return cast(Class) object.dscope.resolve(BuiltinName!"TypeInfo");
	}
	
	auto getClassInfo() {
		return cast(Class) object.dscope.resolve(BuiltinName!"ClassInfo");
	}
	
	auto getClassDowncast() {
		import d.ir.dscope : OverloadSet;
		auto os = cast(OverloadSet) object.dscope.resolve(BuiltinName!"__sd_class_downcast");
		assert(os.set.length == 1);
		
		return cast(Function) os.set[0];
	}
}

