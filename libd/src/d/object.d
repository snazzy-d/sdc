module d.object;

import d.ir.symbol;

import d.context.location;
import d.context.name;

final class ObjectReference {
	private Module object;
	
	this(Module object) {
		this.object = object;
	}
	
	auto getSizeT() {
		return cast(TypeAlias) object.resolve(Location.init, BuiltinName!"size_t");
	}
	
	private auto getClass(Name name) {
		return cast(Class) object.resolve(Location.init, name);
	}
	
	auto getObject() {
		return getClass(BuiltinName!"Object");
	}
	
	auto getTypeInfo() {
		return getClass(BuiltinName!"TypeInfo");
	}
	
	auto getClassInfo() {
		return getClass(BuiltinName!"ClassInfo");
	}
	
	auto getThrowable() {
		return getClass(BuiltinName!"Throwable");
	}
	
	auto getException() {
		return getClass(BuiltinName!"Exception");
	}
	
	auto getError() {
		return getClass(BuiltinName!"Error");
	}
	
	private auto getFunction(Name name) {
		import d.ir.dscope : OverloadSet;
		auto os = cast(OverloadSet) object.resolve(Location.init, name);
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
	
	auto getArrayConcat() {
		auto s = object.resolve(Location.init, BuiltinName!"__sd_array_concat");
		import d.ir.dscope : OverloadSet;
		return cast(OverloadSet) s;
	}
}

