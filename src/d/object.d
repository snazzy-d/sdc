module d.object;

import d.ir.symbol;

import source.location;
import source.name;

final class ObjectReference {
	private Module object;

	this(Module object) {
		this.object = object;
	}

	private auto getSymbol(T)(Name name) {
		return cast(T) object.resolve(Location.init, name);
	}

	private auto getTypeAlias(Name name) {
		return getSymbol!TypeAlias(name);
	}

	auto getSizeT() {
		return getTypeAlias(BuiltinName!"size_t");
	}

	auto getPtrDiffT() {
		return getTypeAlias(BuiltinName!"ptrdiff_t");
	}

	private auto getClass(Name name) {
		return getSymbol!Class(name);
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

	private auto getOverloadableSymbol(T)(Name name) {
		auto s = object.resolve(Location.init, name);
		if (auto t = cast(T) s) {
			return t;
		}

		auto os = cast(OverloadSet) s;
		assert(os.set.length == 1);
		return cast(T) os.set[0];
	}

	private auto getFunction(Name name) {
		return getOverloadableSymbol!Function(name);
	}

	auto getGCalloc() {
		return getFunction(BuiltinName!"__sd_gc_alloc");
	}

	auto getThrow() {
		return getFunction(BuiltinName!"__sd_eh_throw");
	}

	auto getPersonality() {
		return getFunction(BuiltinName!"__sd_eh_personality");
	}

	auto getClassDowncast() {
		return getFunction(BuiltinName!"__sd_class_downcast");
	}

	auto getFinalClassDowncast() {
		return getFunction(BuiltinName!"__sd_final_class_downcast");
	}

	auto getAssertFail() {
		return getFunction(BuiltinName!"__sd_assert_fail");
	}

	auto getAssertFailMsg() {
		return getFunction(BuiltinName!"__sd_assert_fail_msg");
	}

	auto getArrayOutOfBounds() {
		return getFunction(BuiltinName!"__sd_array_outofbounds");
	}

	private auto getTemplate(Name name) {
		return getOverloadableSymbol!Template(name);
	}

	auto getArrayConcat() {
		return getTemplate(BuiltinName!"__sd_array_concat");
	}
}
