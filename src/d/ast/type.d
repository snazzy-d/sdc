module d.ast.type;

import d.ast.ambiguous;
import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;

class Type : Node, Namespace {
	this(Location location) {
		super(location);
	}
	
	abstract Type makeMutable();
	abstract Type makeImmutable();
	abstract Type makeConst();
	abstract Type makeInout();
}

class SimpleStorageClassType : Type {
	private uint storageClass = 0;
	
	enum MUTABLE = 0x00;
	enum IMMUTABLE = 0x01;
	enum CONST = 0x02;
	enum INOUT = 0x03;
	
	enum MASK = ~0x03;
	
	this(Location location) {
		super(location);
	}
	
final:	// Check whenever these operation make sense.
	override Type makeMutable() {
		storageClass &= MASK;
		return this;
	}
	
	override Type makeImmutable() {
		makeMutable();
		storageClass |= IMMUTABLE;
		return this;
	}
	
	override Type makeConst() {
		makeMutable();
		storageClass |= CONST;
		return this;
	}
	
	override Type makeInout() {
		makeMutable();
		storageClass |= INOUT;
		return this;
	}
}

/**
 * Auto types
 */
class AutoType : SimpleStorageClassType {
	this(Location location) {
		super(location);
	}
}

/**
 * All basics types and qualified basic types.
 */
class BasicType : SimpleStorageClassType {
	this(Location location) {
		super(location);
	}
}

import std.traits;
template isBuiltin(T) {
	enum bool isBuiltin = isSomeChar!T || isFloatingPoint!T || is(Unqual!T == void);
}

class BuiltinType(T) if(isBuiltin!T && is(Unqual!T == T)) : BasicType {
	this(Location location) {
		super(location);
	}
}

/**
 * Built in types.
 */
enum Integer {
	Bool,
	Byte,
	Ubyte,
	Short,
	Ushort,
	Int,
	Uint,
	Long,
	Ulong,
}

template IntegerOf(T) {
	static if(!is(T == Unqual!T)) {
		enum IntegerOf = IntegerOf!(Unqual!T);
	} else static if(is(T == bool)) {
		enum IntegerOf = Integer.Bool;
	} else static if(is(T == byte)) {
		enum IntegerOf = Integer.Byte;
	} else static if(is(T == ubyte)) {
		enum IntegerOf = Integer.Ubyte;
	} else static if(is(T == short)) {
		enum IntegerOf = Integer.Short;
	} else static if(is(T == ushort)) {
		enum IntegerOf = Integer.Ushort;
	} else static if(is(T == int)) {
		enum IntegerOf = Integer.Int;
	} else static if(is(T == uint)) {
		enum IntegerOf = Integer.Uint;
	} else static if(is(T == long)) {
		enum IntegerOf = Integer.Long;
	} else static if(is(T == ulong)) {
		enum IntegerOf = Integer.Ulong;
	} else {
		static assert(0, T.stringof ~ " isn't a valid integer type.");
	}
}

class IntegerType : BasicType {
	Integer type;
	
	this(Location location, Integer type) {
		super(location);
		
		this.type = type;
	}
}

/**
 * Type defined by an identifier
 */
class IdentifierType : BasicType {
	Identifier identifier;
	
	this(Location location, Identifier identifier) {
		super(location);
		
		this.identifier = identifier;
	}
}


/**
 * Type defined by typeof(Expression)
 */
class TypeofType : BasicType {
	private Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
}

/**
 * Type defined by typeof(return)
 */
class ReturnType : BasicType {
	this(Location location) {
		super(location);
	}
}

/**
 * Type suffixes
 */
enum TypeSuffixType {
	Pointer,
	StaticArray,
	Slice,
	AssociativeArray,
	AmbiguousArray,
}

class SuffixType : SimpleStorageClassType {
	TypeSuffixType type;
	Type qualified;
	
	this(Location location, TypeSuffixType type, Type qualified) {
		super(location);
		
		this.type = type;
		this.qualified = qualified;
	}
}

/**
 * Pointer types
 */
class PointerType : SuffixType {
	this(Location location, Type qualified) {
		super(location, TypeSuffixType.Pointer, qualified);
	}
}

/**
 * Slice types
 */
class SliceType : SuffixType {
	this(Location location, Type qualified) {
		super(location, TypeSuffixType.Slice, qualified);
	}
}

/**
 * Static array types
 */
class StaticArrayType : SuffixType {
	Expression size;
	
	this(Location location, Type qualified, Expression size) {
		super(location, TypeSuffixType.StaticArray, qualified);
		
		this.size = size;
	}
}

/**
 * Associative array types
 */
class AssociativeArrayType : SuffixType {
	Type keyType;
	
	this(Location location, Type qualified, Type keyType) {
		super(location, TypeSuffixType.AssociativeArray, qualified);
		
		this.keyType = keyType;
	}
}

/**
 * Associative array types
 */
class AmbiguousArrayType : SuffixType {
	TypeOrExpression key;
	
	this(Location location, Type qualified, TypeOrExpression key) {
		super(location, TypeSuffixType.AmbiguousArray, qualified);
		
		this.key = key;
	}
}

