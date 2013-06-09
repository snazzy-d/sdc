module d.ast.type;

import d.ast.adt;
import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.identifier;

import std.traits;

enum TypeQualifier {
	Mutable,
	Inout,
	Const,
	Shared,
	ConstShared,
	Immutable,
}

// XXX: operator overloading ?
auto add(TypeQualifier actual, TypeQualifier added) {
	if((actual == TypeQualifier.Shared && added == TypeQualifier.Const) ||
			(added == TypeQualifier.Shared && actual == TypeQualifier.Const)) {
		return TypeQualifier.ConstShared;
	}
	
	import std.algorithm;
	return max(actual, added);
}

unittest {
	import std.traits;
	foreach(q1; EnumMembers!TypeQualifier) {
		assert(TypeQualifier.Mutable.add(q1) == q1);
		assert(TypeQualifier.Immutable.add(q1) == TypeQualifier.Immutable);
		
		foreach(q2; EnumMembers!TypeQualifier) {
			assert(q1.add(q2) == q2.add(q1));
		}
	}
	
	assert(TypeQualifier.Const.add(TypeQualifier.Immutable) == TypeQualifier.Immutable);
	assert(TypeQualifier.Const.add(TypeQualifier.Inout) == TypeQualifier.Const);
	assert(TypeQualifier.Const.add(TypeQualifier.Shared) == TypeQualifier.ConstShared);
	assert(TypeQualifier.Const.add(TypeQualifier.ConstShared) == TypeQualifier.ConstShared);
	
	assert(TypeQualifier.Immutable.add(TypeQualifier.Inout) == TypeQualifier.Immutable);
	assert(TypeQualifier.Immutable.add(TypeQualifier.Shared) == TypeQualifier.Immutable);
	assert(TypeQualifier.Immutable.add(TypeQualifier.ConstShared) == TypeQualifier.Immutable);
	
	// assert(TypeQualifier.Inout.add(TypeQualifier.Shared) == TypeQualifier.ConstShared);
	assert(TypeQualifier.Inout.add(TypeQualifier.ConstShared) == TypeQualifier.ConstShared);
	
	assert(TypeQualifier.Shared.add(TypeQualifier.ConstShared) == TypeQualifier.ConstShared);
}

bool canConvert(TypeQualifier from, TypeQualifier to) {
	if(from == to) {
		return true;
	}
	
	final switch(to) with(TypeQualifier) {
		case Mutable :
		case Inout :
		case Shared :
		case Immutable :
			// Some qualifier are not safely castable to.
			return false;
		
		case Const :
			return from == Mutable || from == Immutable || from == Inout;
		
		case ConstShared :
			return from == Shared || from == Immutable;
	}
}

abstract class Type : Node {
	TypeQualifier qualifier;
	
	this(Location location) {
		super(location);
	}
	
	bool opEquals(const Type t) const out(isEqual) {
		if(isEqual) {
			assert(qualifier == t.qualifier, "Type can't be equal with different qualifiers.");
		}
	} body {
		assert(0, "comparaision isn't supported for type " ~ typeid(this).toString());
	}

final:
	override bool opEquals(Object o) {
		if(auto t = cast(Type) o) {
			return opEquals(t);
		}
		
		return false;
	}
}

class SuffixType : Type {
	Type type;
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
}

/**
 * All basics types and qualified basic types.
 */
class BasicType : Type {
	this(Location location) {
		super(location);
	}
}

/**
 * An Error occured but an Type is expected.
 * Useful for speculative compilation.
 */
class ErrorType : BasicType {
	string message;
	
	this(Location location, string message = "") {
		super(location);
		
		this.message = message;
	}
}

/**
 * Auto types
 */
class AutoType : Type {
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
	
	override bool opEquals(const Type t) const {
		return typeid(t) is typeid(BooleanType);
	}
	
	bool opEquals(BooleanType t) const {
		return qualifier == t.qualifier;
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
	
	override bool opEquals(const Type t) const {
		if(auto i = cast(IntegerType) t) {
			return this.opEquals(i);
		}
		
		return false;
	}
	
	bool opEquals(const IntegerType t) const {
		return type == t.type && qualifier == t.qualifier;
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
	
	override bool opEquals(const Type t) const {
		if(auto f = cast(IntegerType) t) {
			return this.opEquals(f);
		}
		
		return false;
	}
	
	bool opEquals(const FloatType t) const {
		return type == t.type && qualifier == t.qualifier;
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
	
	override bool opEquals(const Type t) const {
		if(auto c = cast(CharacterType) t) {
			return this.opEquals(c);
		}
		
		return false;
	}
	
	bool opEquals(const CharacterType t) const {
		return type == t.type && qualifier == t.qualifier;
	}
}

/**
 * Void
 */
class VoidType : BasicType {
	this(Location location) {
		super(location);
	}
	
	override bool opEquals(const Type t) const {
		return typeid(t) is typeid(VoidType);
	}
	
	bool opEquals(const VoidType t) const {
		return qualifier == t.qualifier;
	}
}

/**
 * Type defined by an identifier
 */
class IdentifierType : BasicType {
	Identifier identifier;
	
	this(Identifier identifier) {
		super(identifier.location);
		
		this.identifier = identifier;
	}
}

/**
 * Aliased type.
 * Type created via an alias declaration.
 */
class AliasType : BasicType {
	AliasDeclaration dalias;
	
	this(AliasDeclaration dalias) {
		super(dalias.location);
		
		this.dalias = dalias;
	}
	
	override bool opEquals(const Type t) const {
		if(auto a = cast(AliasType) t) {
			return this.opEquals(a);
		}
		
		return false;
	}
	
	bool opEquals(const AliasType t) const {
		return dalias is t.dalias && qualifier == t.qualifier;
	}
}

/**
 * Struct type.
 * Type created via a struct declaration.
 */
class StructType : BasicType {
	StructDeclaration dstruct;
	
	this(StructDeclaration dstruct) {
		super(dstruct.location);
		
		this.dstruct = dstruct;
	}
	
	override bool opEquals(const Type t) const {
		if(auto s = cast(StructType) t) {
			return this.opEquals(s);
		}
		
		return false;
	}
	
	bool opEquals(const StructType t) const {
		return dstruct is t.dstruct && qualifier == t.qualifier;
	}
}

/**
 * Class type.
 * Type created via a class declaration.
 */
class ClassType : BasicType {
	ClassDeclaration dclass;
	
	this(ClassDeclaration dclass) {
		super(dclass.location);
		
		this.dclass = dclass;
	}
	
	override bool opEquals(const Type t) const {
		if(auto c = cast(ClassType) t) {
			return this.opEquals(c);
		}
		
		return false;
	}
	
	bool opEquals(const ClassType t) const {
		return dclass is t.dclass && qualifier == t.qualifier;
	}
}

/**
 * Enum type
 * Type created via a enum declaration.
 */
class EnumType : BasicType {
	EnumDeclaration denum;
	
	this(EnumDeclaration denum) {
		super(denum.location);
		
		this.denum = denum;
	}
	
	override bool opEquals(const Type t) const {
		if(auto e = cast(EnumType) t) {
			return this.opEquals(e);
		}
		
		return false;
	}
	
	bool opEquals(const EnumType t) const {
		return denum is t.denum && qualifier == t.qualifier;
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
 * Pointer type
 */
class PointerType : SuffixType {
	this(Location location, Type type) {
		super(location, type);
	}
	
	override bool opEquals(const Type t) const {
		if(auto p = cast(PointerType) t) {
			return this.opEquals(p);
		}
		
		return false;
	}
	
	bool opEquals(const PointerType t) const {
		return type == t.type && qualifier == t.qualifier;
	}
}

/**
 * Slice types
 */
class SliceType : SuffixType {
	this(Location location, Type type) {
		super(location, type);
	}
	
	override bool opEquals(const Type t) const {
		if(auto p = cast(SliceType) t) {
			return this.opEquals(p);
		}
		
		return false;
	}
	
	bool opEquals(const SliceType t) const {
		return type == t.type && qualifier == t.qualifier;
	}
}

/**
 * Static array types
 */
class StaticArrayType : SuffixType {
	Expression size;
	
	this(Location location, Type type, Expression size) {
		super(location, type);
		
		this.size = size;
	}
}

/**
 * Associative array types
 */
class AssociativeArrayType : SuffixType {
	Type keyType;
	
	this(Location location, Type type, Type keyType) {
		super(location, type);
		
		this.keyType = keyType;
	}
}

/**
 * Associative or static array types
 */
class IdentifierArrayType : SuffixType {
	Identifier identifier;
	
	this(Location location, Type type, Identifier identifier) {
		super(location, type);
		
		this.identifier = identifier;
	}
}

