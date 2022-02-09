module d.common.qualifier;

enum Visibility {
	Private,
	Package,
	Protected,
	Public,
	Export,
}

enum Linkage {
	D,
	C,
	Cpp,
	Windows,
	System,
	Pascal,
	Java,
}

enum Storage {
	Local,
	Capture,
	Static,
	Enum,
}

@property
bool isGlobal(Storage s) {
	return s > Storage.Capture;
}

@property
bool isLocal(Storage s) {
	return !isGlobal(s);
}

unittest {
	with (Storage) {
		assert(Local.isGlobal == false);
		assert(Local.isLocal == true);
		assert(Capture.isGlobal == false);
		assert(Capture.isLocal == true);
		assert(Static.isGlobal == true);
		assert(Static.isLocal == false);
		assert(Enum.isGlobal == true);
		assert(Enum.isLocal == false);
	}
}

enum TypeQualifier {
	Mutable,
	Inout,
	Const,
	Shared,
	ConstShared,
	Immutable,
}

// XXX: operator overloading ?
auto add(TypeQualifier actual, TypeQualifier added) {
	if ((actual == TypeQualifier.Shared && added == TypeQualifier.Const)
		    || (added == TypeQualifier.Shared
			    && actual == TypeQualifier.Const)) {
		return TypeQualifier.ConstShared;
	}

	import std.algorithm;
	return max(actual, added);
}

unittest {
	import std.traits;
	foreach (q1; EnumMembers!TypeQualifier) {
		assert(TypeQualifier.Mutable.add(q1) == q1);
		assert(TypeQualifier.Immutable.add(q1) == TypeQualifier.Immutable);

		foreach (q2; EnumMembers!TypeQualifier) {
			assert(q1.add(q2) == q2.add(q1));
		}
	}

	with (TypeQualifier) {
		assert(Const.add(Immutable) == Immutable);
		assert(Const.add(Inout) == Const);
		assert(Const.add(Shared) == ConstShared);
		assert(Const.add(ConstShared) == ConstShared);

		assert(Immutable.add(Inout) == Immutable);
		assert(Immutable.add(Shared) == Immutable);
		assert(Immutable.add(ConstShared) == Immutable);

		// assert(Inout.add(Shared) == ConstShared);
		assert(Inout.add(ConstShared) == ConstShared);

		assert(Shared.add(ConstShared) == ConstShared);
	}
}

bool canConvert(TypeQualifier from, TypeQualifier to) {
	if (from == to) {
		return true;
	}

	final switch (to) with (TypeQualifier) {
		case Mutable, Inout, Shared, Immutable:
			// Some qualifier are not safely castable to.
			return false;

		case Const:
			return from == Mutable || from == Immutable || from == Inout;

		case ConstShared:
			return from == Shared || from == Immutable;
	}
}

enum ParamKind {
	/// Regular parameter. A slot on the stack will be allocated and value
	/// copied in it when calling the function.
	Regular,
	/// Final parameter. No slot on the stack is created for it, and the
	/// parameter cannot be written to, even when mutable.
	Final,
	/// Ref parameter. The address of the argument is passed instead of the
	/// argument itself and is used as if it was a regular slot on the stack.
	Ref,
}
