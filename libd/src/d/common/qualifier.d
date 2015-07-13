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
bool isNonLocal(Storage s) {
	return s > Storage.Capture;
}

unittest {
	with(Storage) {
		assert(Local.isNonLocal   == false);
		assert(Capture.isNonLocal == false);
		assert(Static.isNonLocal  == true);
		assert(Enum.isNonLocal    == true);
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
	if((actual == TypeQualifier.Shared && added == TypeQualifier.Const) ||
			(added == TypeQualifier.Shared && actual == TypeQualifier.Const)) {
		return TypeQualifier.ConstShared;
	}
	
	import std.algorithm;
	return max(actual, added);
}

unittest {
	import std.traits;
	foreach(q1; EnumMembers!TypeQualifier) {
		assert(TypeQualifier.Mutable.add(q1) == q1);
		assert(TypeQualifier.Immutable.add(q1) == TypeQualifier.Immutable);
		
		foreach(q2; EnumMembers!TypeQualifier) {
			assert(q1.add(q2) == q2.add(q1));
		}
	}
	
	with(TypeQualifier) {
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
	if(from == to) {
		return true;
	}
	
	final switch(to) with(TypeQualifier) {
		case Mutable, Inout, Shared, Immutable:
			// Some qualifier are not safely castable to.
			return false;
		
		case Const:
			return from == Mutable || from == Immutable || from == Inout;
		
		case ConstShared:
			return from == Shared || from == Immutable;
	}
}
