module d.ir.type;

// XXX: type qualifiers, refactor.
import d.ast.base;
import d.ast.qualtype;
import d.ast.type;

import d.ir.symbol;

class Type : AstType {
	Type canonical;
	
	protected this(Type canon = null) {
		this.canonical = canon;
	}
}

alias QualType = d.ast.qualtype.QualType!Type;
alias ParamType = d.ast.qualtype.ParamType!Type;
alias PointerType = d.ast.qualtype.PointerType!Type;
alias SliceType = d.ast.qualtype.SliceType!Type;
alias AssociativeArrayType = d.ast.qualtype.AssociativeArrayType!Type;
alias FunctionType = d.ast.qualtype.FunctionType!Type;
alias DelegateType = d.ast.qualtype.DelegateType!Type;

enum TypeKind {
	None,
	Void,
	Bool,
	Char,
	Wchar,
	Dchar,
	Ubyte,
	Ushort,
	Uint,
	Ulong,
	Ucent,
	Byte,
	Short,
	Int,
	Long,
	Cent,
	Float,
	Double,
	Real,
	Null,
}

bool isChar(TypeKind t) {
	return (t >= TypeKind.Char) && (t <= TypeKind.Dchar);
}

TypeKind integralOfChar(TypeKind t) in {
	assert(isChar(t), "integralOfChar only apply to character types");
} body {
	return cast(TypeKind) (t + 3);
}

unittest {
	assert(integralOfChar(TypeKind.Char) == TypeKind.Ubyte);
	assert(integralOfChar(TypeKind.Wchar) == TypeKind.Ushort);
	assert(integralOfChar(TypeKind.Dchar) == TypeKind.Uint);
}

bool isIntegral(TypeKind t) {
	return (t >= TypeKind.Ubyte) && (t <= TypeKind.Cent);
}

bool isSigned(TypeKind t) in {
	assert(isIntegral(t), "isSigned only apply to integral types");
} body {
	return signed(t) == t;
}

TypeKind unsigned(TypeKind t) in {
	assert(isIntegral(t), "unsigned only apply to integral types");
} body {
	switch(t) with(TypeKind) {
		case Ubyte:
		case Ushort:
		case Uint:
		case Ulong:
		case Ucent:
			return t;
		
		case Byte:
		case Short:
		case Int:
		case Long:
		case Cent:
			return cast(TypeKind) (t - 5);
		
		default:
			assert(0, "unsigned only apply for integral types.");
	}
}

TypeKind signed(TypeKind t) in {
	assert(isIntegral(t), "signed only apply to integral types");
} body {
	switch(t) with(TypeKind) {
		case Ubyte:
		case Ushort:
		case Uint:
		case Ulong:
		case Ucent:
			return cast(TypeKind) (t + 5);
		
		case Byte:
		case Short:
		case Int:
		case Long:
		case Cent:
			return t;
		
		default:
			assert(0, "signed only apply for integral types.");
	}
}

unittest {
	assert(unsigned(TypeKind.Ubyte) == TypeKind.Ubyte);
	assert(unsigned(TypeKind.Ushort) == TypeKind.Ushort);
	assert(unsigned(TypeKind.Uint) == TypeKind.Uint);
	assert(unsigned(TypeKind.Ulong) == TypeKind.Ulong);
	assert(unsigned(TypeKind.Ucent) == TypeKind.Ucent);
	assert(unsigned(TypeKind.Byte) == TypeKind.Ubyte);
	assert(unsigned(TypeKind.Short) == TypeKind.Ushort);
	assert(unsigned(TypeKind.Int) == TypeKind.Uint);
	assert(unsigned(TypeKind.Long) == TypeKind.Ulong);
	assert(unsigned(TypeKind.Cent) == TypeKind.Ucent);
	
	assert(signed(TypeKind.Ubyte) == TypeKind.Byte);
	assert(signed(TypeKind.Ushort) == TypeKind.Short);
	assert(signed(TypeKind.Uint) == TypeKind.Int);
	assert(signed(TypeKind.Ulong) == TypeKind.Long);
	assert(signed(TypeKind.Ucent) == TypeKind.Cent);
	assert(signed(TypeKind.Byte) == TypeKind.Byte);
	assert(signed(TypeKind.Short) == TypeKind.Short);
	assert(signed(TypeKind.Int) == TypeKind.Int);
	assert(signed(TypeKind.Long) == TypeKind.Long);
	assert(signed(TypeKind.Cent) == TypeKind.Cent);
}

bool isFloat(TypeKind t) {
	return (t >= TypeKind.Float) && (t <= TypeKind.Real);
}

final:
/**
 * builtin types
 */
class BuiltinType : Type {
	TypeKind kind;
	
	this(TypeKind kind) {
		super(this);
		
		this.kind = kind;
	}
	
	override string toString(TypeQualifier qual) const {
		final switch (kind) with(TypeKind) {
			case None :
				return "__none__";
			
			case Void :
				return "void";
			
			case Bool :
				return "bool";
			
			case Char :
				return "char";
			
			case Wchar :
				return "wchar";
			
			case Dchar :
				return "dchar";
			
			case Ubyte :
				return "ubyte";
			
			case Ushort :
				return "ushort";
			
			case Uint :
				return "uint";
			
			case Ulong :
				return "ulong";
			
			case Ucent :
				return "ucent";
			
			case Byte :
				return "byte";
			
			case Short :
				return "short";
			
			case Int :
				return "int";
			
			case Long :
				return "long";
			
			case Cent :
				return "cent";
			
			case Float :
				return "float";
			
			case Double :
				return "double";
			
			case Real :
				return "real";
			
			case Null :
				return "typeof(null)";
		}
	}
}

QualType getBuiltin(TypeKind k) {
	return QualType(new BuiltinType(k));
}

/**
 * An Error occured but an Type is expected.
 * Useful for speculative compilation.
 */
class ErrorType : Type {
	Location location;
	string message;
	
	this(Location location, string message = "") {
		super(this);
		
		this.location = location;
		this.message = message;
	}
}

/**
 * Array type
 */
class ArrayType : Type {
	QualType elementType;
	ulong size;
	
	this(QualType elementType, ulong size) {
		this.elementType = elementType;
		this.size = size;
	}
	
	override string toString(TypeQualifier qual) const {
		import std.conv;
		return elementType.toString(qual) ~ "[" ~ to!string(size) ~ "]";
	}
}

/**
 * Aliased type.
 * Type created via an alias declaration.
 */
class AliasType : Type {
	TypeAlias dalias;
	
	this(TypeAlias dalias) {
		this.dalias = dalias;
	}
	
	override string toString(TypeQualifier) const {
		return dalias.name;
	}
}

/**
 * Struct type.
 * Type created via a struct declaration.
 */
class StructType : Type {
	Struct dstruct;
	
	this(Struct dstruct) {
		this.dstruct = dstruct;
	}
	
	override string toString(TypeQualifier) const {
		return dstruct.name;
	}
}

/**
 * Class type.
 * Type created via a class declaration.
 */
class ClassType : Type {
	Class dclass;
	
	this(Class dclass) {
		this.dclass = dclass;
	}
	
	override string toString(TypeQualifier) const {
		return dclass.name;
	}
}

/**
 * Enum type
 * Type created via a enum declaration.
 */
class EnumType : Type {
	Enum denum;
	
	this(Enum denum) {
		this.denum = denum;
	}
	
	override string toString(TypeQualifier) const {
		return denum.name;
	}
}

