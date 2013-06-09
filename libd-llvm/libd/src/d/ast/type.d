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

abstract class Type {
	TypeQualifier qualifier;
	Type canonical;
	
	bool opEquals(const Type t) const out(isEqual) {
		if(isEqual) {
			assert(qualifier == t.qualifier, "Type can't be equal with different qualifiers.");
		}
	} body {
		assert(0, "comparaision isn't supported for type " ~ typeid(this).toString());
	}
	
	// TODO: make that abstract
	/* abstract */ string toUnqualString() const {
		// assert(0, "Not implemented");
		return typeid(this).toString();
	}

final:
	override bool opEquals(Object o) {
		if(auto t = cast(Type) o) {
			return opEquals(t);
		}
		
		return false;
	}
	
	final override string toString() {
		const t = this;
		
		return t.toString();
	}
	
	final string toString() const {
		auto s = toUnqualString();
		
		final switch(qualifier) with(TypeQualifier) {
			case Mutable:
				return s;
			
			case Inout:
				return "inout(" ~ s ~ ")";
			
			case Const:
				return "const(" ~ s ~ ")";
			
			case Shared:
				return "shared(" ~ s ~ ")";
			
			case ConstShared:
				assert(0, "const shared isn't supported");
			
			case Immutable:
				return "immutable(" ~ s ~ ")";
		}
	}
}

abstract class SuffixType : Type {
	Type type;
	
	this(Type type) {
		this.type = type;
	}
}

/**
 * All basics types and qualified basic types.
 */
abstract class BasicType : Type {}

final:
/**
 * An Error occured but an Type is expected.
 * Useful for speculative compilation.
 */
class ErrorType : BasicType {
	Location location;
	string message;
	
	this(Location location, string message = "") {
		this.location = location;
		this.message = message;
	}
}

/**
 * Auto types
 */
class AutoType : Type {}

/**
 * Boolean type.
 */
class BooleanType : BasicType {
	this() {
		canonical = this;
	}
	
	override bool opEquals(const Type t) const {
		return typeid(t) is typeid(BooleanType);
	}
	
	bool opEquals(BooleanType t) const {
		return qualifier == t.qualifier;
	}
	
	override string toUnqualString() const {
		return "bool";
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
	
	this(Integer type) {
		this.type = type;
		
		canonical = this;
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
	
	override string toUnqualString() const {
		final switch(type) with(Integer) {
			case Byte:
				return "byte";
			
			case Ubyte:
				return "ubyte";
			
			case Short:
				return "short";
			
			case Ushort:
				return "ushort";
			
			case Int:
				return "int";
			
			case Uint:
				return "uint";
			
			case Long:
				return "long";
			
			case Ulong:
				return "ulong";
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
	
	this(Float type) {
		this.type = type;
		
		canonical = this;
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
	
	override string toUnqualString() const {
		final switch(type) with(Float) {
			case Float:
				return "float";
			
			case Double:
				return "double";
			
			case Real:
				return "real";
		}
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
	
	this(Character type) {
		this.type = type;
		
		canonical = this;
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
	
	override string toUnqualString() const {
		final switch(type) with(Character) {
			case Char:
				return "char";
			
			case Wchar:
				return "wchar";
			
			case Dchar:
				return "dchar";
		}
	}
}

/**
 * Void
 */
class VoidType : BasicType {
	this() {
		canonical = this;
	}
	
	override bool opEquals(const Type t) const {
		return typeid(t) is typeid(VoidType);
	}
	
	bool opEquals(const VoidType t) const {
		return qualifier == t.qualifier;
	}
	
	override string toUnqualString() const {
		return "void";
	}
}

/**
 * Type defined by an identifier
 */
class IdentifierType : BasicType {
	Identifier identifier;
	
	this(Identifier identifier) {
		this.identifier = identifier;
	}
}

/**
 * Pointer type
 */
class PointerType : SuffixType {
	this(Type type) {
		super(type);
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
	
	override string toUnqualString() const {
		return ((qualifier == type.qualifier)? type.toUnqualString() : type.toString()) ~ "*";
	}
}

/**
 * Slice types
 */
class SliceType : SuffixType {
	this(Type type) {
		super(type);
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
	
	override string toUnqualString() const {
		return ((qualifier == type.qualifier)? type.toUnqualString() : type.toString()) ~ "[]";
	}
}

/**
 * Static array types
 */
class StaticArrayType : SuffixType {
	Expression size;
	
	this(Type type, Expression size) {
		super(type);
		
		this.size = size;
	}
}

/**
 * Associative array types
 */
class AssociativeArrayType : Type {
	Type keyType;
	Type valueType;
	
	this(Type valueType, Type keyType) {
		this.keyType = keyType;
		this.valueType = valueType;
	}
}

/**
 * Associative or static array types
 */
class IdentifierArrayType : Type {
	Identifier identifier;
	Type type;
	
	this(Type type, Identifier identifier) {
		this.identifier = identifier;
		this.type = type;
	}
}

/**
 * Aliased type.
 * Type created via an alias declaration.
 */
class AliasType : BasicType {
	AliasDeclaration dalias;
	
	this(AliasDeclaration dalias) {
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
	
	override string toUnqualString() const {
		return dalias.name;
	}
}

/**
 * Struct type.
 * Type created via a struct declaration.
 */
class StructType : BasicType {
	StructDeclaration dstruct;
	
	this(StructDeclaration dstruct) {
		this.dstruct = dstruct;
		
		// canonical = this;
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
	
	override string toUnqualString() const {
		return dstruct.name;
	}
}

/**
 * Class type.
 * Type created via a class declaration.
 */
class ClassType : BasicType {
	ClassDeclaration dclass;
	
	this(ClassDeclaration dclass) {
		this.dclass = dclass;
		
		// canonical = this;
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
	
	override string toUnqualString() const {
		return dclass.name;
	}
}

/**
 * Enum type
 * Type created via a enum declaration.
 */
class EnumType : BasicType {
	EnumDeclaration denum;
	
	this(EnumDeclaration denum) {
		this.denum = denum;
		
		// canonical = this;
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
	
	override string toUnqualString() const {
		return denum.name;
	}
}

/**
 * Type defined by typeof(Expression)
 */
class TypeofType : BasicType {
	Expression expression;
	
	this(Expression expression) {
		this.expression = expression;
	}
}

/**
 * Type defined by typeof(return)
 */
class ReturnType : BasicType {}

