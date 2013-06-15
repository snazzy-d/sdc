module d.semantic.mangler;

import d.semantic.semantic;

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
	
	string visit(AliasType t) {
		auto a = t.dalias;
		scheduler.require(a);
		
		return a.mangle;
	}
	
	string visit(StructType t) {
		auto s = t.dstruct;
		scheduler.require(s);
		
		return s.mangle;
	}
	
	string visit(ClassType t) {
		auto c = t.dclass;
		scheduler.require(c);
		
		return c.mangle;
	}
	
	string visit(EnumType t) {
		auto e = t.denum;
		scheduler.require(e);
		
		return e.mangle;
	}
	
	string visit(BooleanType t) {
		return "b";
	}
	
	private auto mangleParameter(Parameter p) {
		return (p.isReference?"K":"") ~ visit(p.type);
	}
	
	private auto mangleLinkage(string linkage) {
		switch(linkage) {
			case "D" :
				return "F";
			
			case "C" :
				return "U";
			
			case "Windows" :
				return "W";
			
			case "Pascal" :
				return "V";
			
			case "C++" :
				return "R";
			
			default:
				assert(0, "Linkage " ~ linkage ~ " is not supported.");
		}
	}
	
	string visit(FunctionType t) {
		return mangleLinkage(t.linkage) ~ t.parameters.map!(p => mangleParameter(p)).join() ~ "Z" ~ visit(t.returnType);
	}
	
	string visit(DelegateType t) {
		return "D" ~ mangleLinkage(t.linkage) ~ mangleParameter(t.context) ~ t.parameters.map!(p => mangleParameter(p)).join() ~ "Z" ~ visit(t.returnType);
	}
}

