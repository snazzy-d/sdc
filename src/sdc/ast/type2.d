module sdc.ast.type2;

import sdc.location;
import sdc.ast.base2;
import sdc.ast.declaration2;
import sdc.ast.expression2;
import sdc.ast.identifier2;

class Type : Node {
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

template isBuiltin(T) {
	import std.traits;
	
	enum bool isBuiltin = isNumeric!T || isSomeChar!T || is(Unqual!T == bool) || is(Unqual!T == void);
}

/**
 * All basics types and qualified basic types.
 */
class BasicType : SimpleStorageClassType, Namespace {
	this(Location location) {
		super(location);
	}
}

import std.traits;
template builtinType(T) if(isBuiltin!T && is(T == Unqual!T)) {
	class BuiltinType : BasicType {
		private this() {
			super(Location.init);
		}
	}
	
	immutable BuiltinType builtinType;
	
	static this() {
		builtinType = new immutable(BuiltinType)();
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
	Associative,
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
 * Pointer Types
 */
class PointerType : SuffixType {
	this(Location location, Type qualified) {
		super(location, TypeSuffixType.Pointer, qualified);
	}
}

/**
 * Slice Types
 */
class SliceType : SuffixType {
	this(Location location, Type qualified) {
		super(location, TypeSuffixType.Slice, qualified);
	}
}

/**
 * Function types
 */
class FunctionType : SimpleStorageClassType {
	Type returnType;
	Parameter[] parameters;
	
	this(Location location, Type returnType, Parameter[] parameters) {
		super(location);
		
		this.returnType = returnType;
		this.parameters = parameters;
	}
}

/**
 * Delegate types
 */
class DelegateType : FunctionType {
	this(Location location, Type returnType, Parameter[] parameters) {
		super(location, returnType, parameters);
	}
}

/**
 * Function and delegate parameters.
 */
class Parameter : Node {
	Type type;
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
}

class NamedParameter : Parameter {
	string name;
	
	this(Location location, Type type, string name) {
		super(location, type);
		
		this.name = name;
	}
}

class InitializedParameter : NamedParameter {
	Expression value;
	
	this(Location location, Type type, string name, Expression value) {
		super(location, type, name);
		
		this.value = value;
	}
}

