module d.semantic.mangler;

import d.semantic.semantic;

import std.algorithm;
import std.array;

struct TypeMangler {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	import d.ir.type;
	string visit(QualType t) {
		return this.dispatch(t.type);
	}
	
	string visit(BuiltinType t) {
		final switch(t.kind) with(TypeKind) {
			case None :
				assert(0, "none should never be mangled");
			
			case Void :
				return "v";
			
			case Bool :
				return "b";
			
			case Char :
				return "a";
			
			case Wchar :
				return "u";
			
			case Dchar :
				return "w";
			
			case Ubyte :
				return "h";
			
			case Ushort :
				return "t";
			
			case Uint :
				return "k";
			
			case Ulong :
				return "m";
			
			case Ucent :
				assert(0, "mangle for ucent not Implemented");
			
			case Byte :
				return "g";
			
			case Short :
				return "s";
			
			case Int :
				return "i";
			
			case Long :
				return "l";
			
			case Cent :
				assert(0, "mangle for cent not Implemented");
			
			case Float :
				return "f";
			
			case Double :
				return "d";
			
			case Real :
				return "e";
			
			case Null :
				assert(0, "mangle for typeof(null) not Implemented");
		}
	}
	
	string visit(PointerType t) {
		return "P" ~ visit(t.pointed);
	}
	
	string visit(SliceType t) {
		return "A" ~ visit(t.sliced);
	}
	
	string visit(AliasType t) {
		auto a = t.dalias;
		scheduler.require(a);
		
		return a.mangle;
	}
	
	string visit(StructType t) {
		auto s = t.dstruct;
		scheduler.require(s, Step.Populated);
		
		return s.mangle;
	}
	
	string visit(ClassType t) {
		auto c = t.dclass;
		scheduler.require(c, Step.Populated);
		
		return c.mangle;
	}
	
	string visit(EnumType t) {
		auto e = t.denum;
		scheduler.require(e);
		
		return e.mangle;
	}
	
	string visit(ContextType t) {
		return "M";
	}
	
	private auto mangleParam(ParamType t) {
		return (t.isRef?"K":"") ~ visit(QualType(t.type, t.qualifier));
	}
	
	import d.ast.base;
	private auto mangleLinkage(Linkage linkage) {
		switch(linkage) with(Linkage) {
			case D :
				return "F";
			
			case C :
				return "U";
			/+
			case Windows :
				return "W";
			
			case Pascal :
				return "V";
			
			case CXX :
				return "R";
			+/
			default:
				import std.conv;
				assert(0, "Linkage " ~ to!string(linkage) ~ " is not supported.");
		}
	}
	
	string visit(FunctionType t) {
		return mangleLinkage(t.linkage) ~ t.paramTypes.map!(p => mangleParam(p)).join() ~ "Z" ~ mangleParam(t.returnType);
	}
	
	string visit(DelegateType t) {
		return "D" ~ mangleLinkage(t.linkage) ~ mangleParam(t.context) ~ t.paramTypes.map!(p => mangleParam(p)).join() ~ "Z" ~ mangleParam(t.returnType);
	}
}

struct ValueMangler {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	import d.ir.expression, std.conv;
	string visit(CompileTimeExpression e) {
		return this.dispatch(e);
	}
	
	string visit(BooleanLiteral e) {
		return to!string(cast(ubyte) e.value);
	}
	
	string visit(IntegerLiteral!true e) {
		return e.value >= 0
			? e.value.to!string()
			: "N" ~ to!string(-e.value);
	}
	
	string visit(IntegerLiteral!false e) {
		return e.value.to!string();
	}
}

