module d.semantic.sizeof;

import d.semantic.semantic;

import d.ast.adt;
import d.ast.declaration;
import d.ast.type;

final class SizeofCalculator {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	uint visit(Type t) {
		return this.dispatch!(function uint(Type t) {
			assert(0, "size of type " ~ typeid(t).toString() ~ " is unknown.");
		})(t);
	}
	
	uint visit(BooleanType t) {
		return 1;
	}
	
	uint visit(IntegerType t) {
		final switch(t.type) {
			case Integer.Byte, Integer.Ubyte :
				return 1;
			
			case Integer.Short, Integer.Ushort :
				return 2;
			
			case Integer.Int, Integer.Uint :
				return 4;
			
			case Integer.Long, Integer.Ulong :
				return 8;
		}
	}
	
	uint visit(FloatType t) {
		final switch(t.type) {
			case Float.Float :
				return 4;
			
			case Float.Double :
				return 8;
			
			case Float.Real :
				return 10;
		}
	}
	
	uint visit(CharacterType t) {
		final switch(t.type) {
			case Character.Char :
				return 1;
			
			case Character.Wchar :
				return 2;
			
			case Character.Dchar :
				return 4;
		}
	}
	
	uint visit(EnumType t) {
		return visit(t.type);
	}
	
	uint visit(SymbolType t) {
		return visit(t.symbol);
	}
	
	uint visit(TypeSymbol s) {
		return this.dispatch!(function uint(TypeSymbol s) {
			assert(0, "size of type designed by " ~ typeid(s).toString() ~ " is unknown.");
		})(s);
	}
	
	uint visit(AliasDeclaration a) {
		return visit(a.type);
	}
}

