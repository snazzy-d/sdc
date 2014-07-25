module d.semantic.sizeof;

import d.semantic.semantic;

import d.ir.type;

struct SizeofVisitor {
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
				assert(0, "none shall never be!");
			case Void :
				assert(0, "void.sizeof not is Implemented");
			
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
				return 16;
			
			case Byte :
				return 1;
			
			case Short :
				return 2;
			
			case Int :
				return 4;
			
			case Long :
				return 8;
			
			case Cent :
				return 16;
			
			case Float :
				return 4;
			
			case Double :
				return 8;
			
			case Real :
			case Null :
				assert(0, "real.sizeof or typeof(null).sizeof is not Implemented");
		}
	}
	
	uint visit(PointerType t) {
		return 8;
	}
	
	uint visit(SliceType t) {
		return 2*8;
	}
	
	uint visit(ArrayType t) {
		return cast(uint) (visit(t.elementType) * t.size);
	}
	
	uint visit(AliasType t) {
		auto a = t.dalias;
		scheduler.require(a);
		
		return visit(a.type);
	}
	
	uint visit(StructType t) {
		assert(0, "struct.sizeof is not implemented.");
	}
	
	uint visit(ClassType t) {
		assert(0, "class.sizeof is not implemented.");
	}
	
	uint visit(EnumType t) {
		auto e = t.denum;
		scheduler.require(e);
		
		return visit(e.type);
	}
}

