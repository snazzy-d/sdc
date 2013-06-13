module d.ast.base;

public import d.node;
public import d.location;

enum Visibility {
	Public,
	Private,
	Protected,
	Package,
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
	
	assert(TypeQualifier.Const.add(TypeQualifier.Immutable) == TypeQualifier.Immutable);
	assert(TypeQualifier.Const.add(TypeQualifier.Inout) == TypeQualifier.Const);
	assert(TypeQualifier.Const.add(TypeQualifier.Shared) == TypeQualifier.ConstShared);
	assert(TypeQualifier.Const.add(TypeQualifier.ConstShared) == TypeQualifier.ConstShared);
	
	assert(TypeQualifier.Immutable.add(TypeQualifier.Inout) == TypeQualifier.Immutable);
	assert(TypeQualifier.Immutable.add(TypeQualifier.Shared) == TypeQualifier.Immutable);
	assert(TypeQualifier.Immutable.add(TypeQualifier.ConstShared) == TypeQualifier.Immutable);
	
	// assert(TypeQualifier.Inout.add(TypeQualifier.Shared) == TypeQualifier.ConstShared);
	assert(TypeQualifier.Inout.add(TypeQualifier.ConstShared) == TypeQualifier.ConstShared);
	
	assert(TypeQualifier.Shared.add(TypeQualifier.ConstShared) == TypeQualifier.ConstShared);
}

bool canConvert(TypeQualifier from, TypeQualifier to) {
	if(from == to) {
		return true;
	}
	
	final switch(to) with(TypeQualifier) {
		case Mutable :
		case Inout :
		case Shared :
		case Immutable :
			// Some qualifier are not safely castable to.
			return false;
		
		case Const :
			return from == Mutable || from == Immutable || from == Inout;
		
		case ConstShared :
			return from == Shared || from == Immutable;
	}
}

