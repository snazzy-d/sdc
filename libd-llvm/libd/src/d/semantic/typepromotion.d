module d.semantic.typepromotion;

import d.semantic.semantic;

import d.ir.symbol;
import d.ir.type;

import d.exception;
import d.location;

import std.algorithm;

QualType getPromotedType(Type lhs, Type rhs) {
	return TypePromoter(rhs).visit(lhs);
}

struct TypePromoter {
	Type rhs;
	
	this(Type rhs) {
		this.rhs = rhs;
	}
	
	QualType visit(Type t) {
		return this.dispatch!(function QualType(Type t) {
			assert(0, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	QualType visit(BuiltinType t) {
		return BuiltinHandler(t.kind).visit(rhs);
	}
	
	QualType visit(PointerType t) {
		return PointerHandler(t.pointed.type).visit(rhs);
	}
	
	QualType visit(ClassType t) {
		return ClassHandler(t.dclass).visit(rhs);
	}
	
	QualType visit(EnumType t) {
		if(auto bt = cast(BuiltinType) t.denum.type) {
			return visit(bt);
		}
		
		throw new CompileException(t.denum.location, "Enum are of type int");
	}
	
	QualType visit(AliasType t) {
		return visit(t.dalias.type.type);
	}
}

struct BuiltinHandler {
	TypeKind lhs;
	
	this(TypeKind lhs) {
		this.lhs = lhs;
	}
	
	QualType visit(Type t) {
		return this.dispatch!(function QualType(Type t) {
			assert(0, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	QualType visit(BuiltinType t) {
		return getBuiltin(promoteBuiltin(t.kind, lhs));
	}
	
	QualType visit(EnumType t) {
		if(auto bt = cast(BuiltinType) t.denum.type) {
			return visit(bt);
		}
		
		throw new CompileException(t.denum.location, "Enum are of type int");
	}
	
	QualType visit(AliasType t) {
		return visit(t.dalias.type.type);
	}
}

TypeKind promoteBuiltin(TypeKind t1, TypeKind t2) {
	if(t1 > t2) swap(t1, t2);
	
	assert(t1 <= t2);
	final switch(t1) with(TypeKind) {
		case None :
			assert(0, "Not Implemented");
		
		case Void :
			assert(t2 == Void);
			
			return Void;
		
		case Bool :
			return promoteBuiltin(Int, t2);
		
		case Char :
		case Wchar :
		case Dchar :
			return promoteBuiltin(Uint, t2);
		
		case Ubyte :
		case Ushort :
			return promoteBuiltin(Int, t2);
		
		case Uint :
			auto ret = promoteBuiltin(Int, t2);
			return (ret == Int)? Uint : ret;
		
		case Ulong :
			auto ret = promoteBuiltin(Long, t2);
			return (ret == Long)? Ulong : ret;
		
		case Ucent :
			auto ret = promoteBuiltin(Cent, t2);
			return (ret == Cent)? Ucent : ret;
		
		case Byte :
		case Short :
			return promoteBuiltin(Int, t2);
		
		case Int :
		case Long :
		case Cent :
			if(t2 <= Cent) {
				return t2;
			}
			
			assert(0, "Not Implemented");
		
		case Float :
		case Double :
		case Real :
		case Null :
			assert(0, "Not Implemented");
	}
}

struct PointerHandler {
	Type pointed;
	
	this(Type pointed) {
		this.pointed = pointed;
	}
	
	QualType visit(Type t) {
		return this.dispatch!(function QualType(Type t) {
			assert(0, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	QualType visit(PointerType t) {
		// Consider pointed.
		return QualType(t);
	}
	
	QualType visit(BuiltinType t) {
		if (t.kind == TypeKind.Null) {
			return QualType(new PointerType(QualType(pointed)));
		}
		
		assert(0, typeid(t).toString() ~ " is not supported");
	}
}

struct ClassHandler {
	Class lhs;
	
	this(Class lhs) {
		this.lhs = lhs;
	}
	
	QualType visit(Type t) {
		return this.dispatch!(function QualType(Type t) {
			assert(0, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	QualType visit(BuiltinType t) {
		if(t.kind == TypeKind.Null) {
			return QualType(new ClassType(lhs));
		}
		
		assert(0, "Can't cast class to " ~ typeid(t).toString());
	}
	
	QualType visit(ClassType t) {
		// Find a common superclass.
		auto r = t.dclass;
		
		auto lup = lhs;
		do {
			// Avoid allocation when possible.
			if(r is lup) {
				return QualType(t);
			}
			
			auto rup = r.base;
			while(rup !is rup.base) {
				if(rup is lup) {
					return QualType(new ClassType(rup));
				}
				
				rup = rup.base;
			}
			
			lup = lup.base;
		} while(lup !is lup.base);
		
		// lup must be Object by now.
		return QualType(new ClassType(lup));
	}
}

