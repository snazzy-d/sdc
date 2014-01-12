module d.semantic.object;

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
}

