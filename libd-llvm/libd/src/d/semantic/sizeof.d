module d.semantic.sizeof;

import d.semantic.semantic;

import d.ir.type;

final class SizeofCalculator {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	uint visit(QualType t) {
		return visit(t.type);
	}
	
	uint visit(Type t) {
		return this.dispatch!(function uint(Type t) {
			assert(0, "size of type " ~ typeid(t).toString() ~ " is unknown.");
		})(t);
	}
	
	uint visit(BuiltinType t) {
		final switch(t.kind) with(TypeKind) {
			case None :
			case Void :
				assert(0, "Not Implemented");
			
			case Bool :
				return 1;
			
			case Char :
				return 1;
			
			case Wchar :
				return 2;
			
			case Dchar :
				return 4;
			
			case Ubyte :
				return 1;
			
			case Ushort :
				return 2;
			
			case Uint :
				return 4;
			
			case Ulong :
				return 8;
			
			case Ucent :
				assert(0, "Not Implemented");
			
			case Byte :
				return 1;
			
			case Short :
				return 2;
			
			case Int :
				return 4;
			
			case Long :
				return 8;
			
			case Cent :
				assert(0, "Not Implemented");
			
			case Float :
				return 2;
			
			case Double :
				return 4;
			
			case Real :
			case Null :
				assert(0, "Not Implemented");
		}
	}
	
	uint visit(AliasType t) {
		auto a = t.dalias;
		scheduler.require(a);
		
		return visit(a.type);
	}
	
	uint visit(StructType t) {
		assert(0, "Struct.sizeof is not implemented.");
	}
	
	uint visit(ClassType t) {
		assert(0, "Struct.sizeof is not implemented.");
	}
	
	uint visit(EnumType t) {
		auto e = t.denum;
		scheduler.require(e);
		
		return visit(e.type);
	}
}

