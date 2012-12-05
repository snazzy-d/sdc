module d.pass.mangler;

import d.pass.base;
import d.pass.semantic;

import d.ast.adt;
import d.ast.dfunction;
import d.ast.type;

import std.algorithm;
import std.array;

final class TypeMangler {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	string visit(Type t) {
		return this.dispatch(t);
	}
	
	string visit(SymbolType t) {
		return scheduler.require(t.symbol).mangle;
	}
	
	string visit(BooleanType t) {
		return "b";
	}
	
	string visit(IntegerType t) {
		final switch(t.type) {
			case Integer.Byte :
				return "g";
			
			case Integer.Ubyte :
				return "h";
			
			case Integer.Short :
				return "s";
			
			case Integer.Ushort :
				return "t";
			
			case Integer.Int :
				return "i";
			
			case Integer.Uint :
				return "k";
			
			case Integer.Long :
				return "l";
			
			case Integer.Ulong :
				return "m";
		}
	}
	
	string visit(FloatType t) {
		final switch(t.type) {
			case Float.Float :
				return "f";
			
			case Float.Double :
				return "d";
			
			case Float.Real :
				return "e";
		}
	}
	
	string visit(CharacterType t) {
		final switch(t.type) {
			case Character.Char :
				return "a";
			
			case Character.Wchar :
				return "u";
			
			case Character.Dchar :
				return "w";
		}
	}
	
	string visit(VoidType t) {
		return "v";
	}
	
	string visit(PointerType t) {
		return "P" ~ visit(t.type);
	}
	
	string visit(SliceType t) {
		return "A" ~ visit(t.type);
	}
	
	string visit(EnumType t) {
		return scheduler.require(t.declaration).mangle;
	}
	
	string visit(FunctionType t) {
		string linkage;
		switch(t.linkage) {
			case "D" :
				linkage = "F";
				break;
			
			case "C" :
				linkage = "U";
				break;
			
			case "Windows" :
				linkage = "W";
				break;
			
			case "Pascal" :
				linkage = "V";
				break;
			
			case "C++" :
				linkage = "R";
				break;
			
			default:
				assert(0, "Linkage " ~ t.linkage ~ " is not supported.");
		}
		
		return linkage ~ t.parameters.map!(p => (p.isReference?"K":"") ~ visit(p.type)).join() ~ "Z" ~ visit(t.returnType);
	}
}

