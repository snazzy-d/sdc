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
	
	auto getThrowable() {
		return cast(Class) object.dscope.resolve(BuiltinName!"Throwable");
	}
	
	auto getException() {
		return cast(Class) object.dscope.resolve(BuiltinName!"Exception");
	}
	
	auto getError() {
		return cast(Class) object.dscope.resolve(BuiltinName!"Error");
	}
	
	private auto getFunction(Name name) {
		import d.ir.dscope : OverloadSet;
		auto os = cast(OverloadSet) object.dscope.resolve(name);
		assert(os.set.length == 1);
		
		return cast(Function) os.set[0];
	}
	
	auto getClassDowncast() {
		return getFunction(BuiltinName!"__sd_class_downcast");
	}
	
	auto getThrow() {
		return getFunction(BuiltinName!"__sd_eh_throw");
	}
	
	auto getPersonality() {
		return getFunction(BuiltinName!"__sd_eh_personality");
	}
}

