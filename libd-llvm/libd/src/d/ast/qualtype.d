module d.ast.qualtype;

import d.ast.base;
import d.ast.type;

struct QualType(T) if(is(T : AstType)) {
	T type;
	TypeQualifier qualifier;
	
	this(T type, TypeQualifier qual = TypeQualifier.Mutable) {
		this.type = type;
		qualifier = qual;
	}
	
	// XXX: for some reasons, dmd messes with inout so I have to duplicate.
	this(const T type, TypeQualifier qual = TypeQualifier.Mutable) const {
		this.type = type;
		qualifier = qual;
	}
	
	string toString(TypeQualifier qual = TypeQualifier.Mutable) const {
		auto s = type.toString(qual);
		
		if(qualifier == qual) return s;
		
		final switch(qualifier) with(TypeQualifier) {
			case Mutable:
				return s;
			
			case Inout:
				return "inout(" ~ s ~ ")";
			
			case Const:
				return "const(" ~ s ~ ")";
			
			case Shared:
				return "shared(" ~ s ~ ")";
			
			case ConstShared:
				assert(0, "const shared isn't supported");
			
			case Immutable:
				return "immutable(" ~ s ~ ")";
		}
	}
}

struct ParamType(T) if(is(T : AstType)) {
	T type;
	
	import std.bitmanip;
	mixin(bitfields!(
		TypeQualifier, "qualifier", 3,
		bool, "isRef", 1,
		bool, "isScope", 1,
		bool, "isFinal", 1,
		int, "", 2,
	));
	
	this(QualType!T t, bool isRef) {
		type = t.type;
		qualifier = t.qualifier;
		this.isRef = isRef;
	}
	
	this(T t, bool isRef) {
		this(QualType!T(t), isRef);
	}
	
	string toString(TypeQualifier qual = TypeQualifier.Mutable) const {
		alias DMD_BUG_WORKAROUND = const(QualType!T);
		auto ret = DMD_BUG_WORKAROUND(type, qualifier).toString(qual);
		
		if(isRef) ret = "ref " ~ ret;
		if(isScope) ret = "scope " ~ ret;
		
		return ret;
	}
}

