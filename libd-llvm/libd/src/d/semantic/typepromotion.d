module d.semantic.typepromotion;

import d.semantic.semantic;

import d.ir.type;

import d.exception;
import d.location;

import std.algorithm;

// TODO: this is complete bullshit. Must be trashed and redone.
QualType getPromotedType(Location location, Type t1, Type t2) {
	struct T2Handler {
		TypeKind t1type;
		
		this(TypeKind t1type) {
			this.t1type = t1type;
		}
		
		QualType visit(Type t) {
			return this.dispatch!(function QualType(Type t) {
				assert(0, typeid(t).toString() ~ " is not supported");
			})(t);
		}
		
		QualType visit(BuiltinType t) {
			return getBuiltin(promoteBuiltin(t.kind, t1type));
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
	
	struct T1Handler {
		QualType visit(Type t) {
			return this.dispatch!(function QualType(Type t) {
				assert(0, typeid(t).toString() ~ " is not supported");
			})(t);
		}
		
		QualType visit(BuiltinType t) {
			return T2Handler(t.kind).visit(t2);
		}
		
		QualType visit(PointerType t) {
			// FIXME: check RHS.
			return QualType(t);
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
	
	return T1Handler().visit(t1);
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

