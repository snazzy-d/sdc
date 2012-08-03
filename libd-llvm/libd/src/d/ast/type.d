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
	
	Expression initExpression(Location location) {
		assert(0, "init not supported for this type " ~ typeid(this).toString());
	}
	
	override Declaration resolve(Scope s) {
		assert(0, "resolve not implemented for" ~ typeid(this).toString());
	}
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
	enum bool isBuiltin = is(Unqual!T == void);
}

class BuiltinType(T) if(isBuiltin!T && is(Unqual!T == T)) : BasicType {
	this(Location location) {
		super(location);
	}
}

/**
 * Boolean type.
 */
class BooleanType : BasicType {
	this(Location location) {
		super(location);
	}
	
	override Expression initExpression(Location location) {
		return makeLiteral(location, false);
	}
}

/**
 * Built in integer types.
 */
enum Integer {
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
	
	override Expression initExpression(Location location) {
		if(type % 2) {
			return new IntegerLiteral!true(location, 0, this);
		} else {
			return new IntegerLiteral!false(location, 0, this);
		}
	}
}

/**
 * Built in float types.
 */
enum Float {
	Float,
	Double,
	Real,
}

template FloatOf(T) {
	static if(!is(T == Unqual!T)) {
		enum FloatOf = FloatOf!(Unqual!T);
	} else static if(is(T == float)) {
		enum FloatOf = Float.Float;
	} else static if(is(T == double)) {
		enum FloatOf = Float.Double;
	} else static if(is(T == real)) {
		enum FloatOf = Float.Real;
	} else {
		static assert(0, T.stringof ~ " isn't a valid float type.");
	}
}

class FloatType : BasicType {
	Float type;
	
	this(Location location, Float type) {
		super(location);
		
		this.type = type;
	}
	
	override Expression initExpression(Location location) {
		return new FloatLiteral(location, float.nan, this);
	}
}

/**
 * Built in char types.
 */
enum Character {
	Char,
	Wchar,
	Dchar,
}

template CharacterOf(T) {
	static if(!is(T == Unqual!T)) {
		enum CharacterOf = CharacterOf!(Unqual!T);
	} else static if(is(T == char)) {
		enum CharacterOf = Character.Char;
	} else static if(is(T == wchar)) {
		enum CharacterOf = Character.Wchar;
	} else static if(is(T == dchar)) {
		enum CharacterOf = Character.Dchar;
	} else {
		static assert(0, T.stringof ~ " isn't a valid character type.");
	}
}

class CharacterType : BasicType {
	Character type;
	
	this(Location location, Character type) {
		super(location);
		
		this.type = type;
	}
	
	override Expression initExpression(Location location) {
		return new CharacterLiteral(location, [char.init], this);
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
	Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
	
	override Expression initExpression(Location location) {
		// TODO: remove in the future.
		scope(failure) {
			import std.stdio;
			writeln(typeid({ return expression.type; }()).toString() ~ " have no .init");
		}
		
		return expression.type.initExpression(location);
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

