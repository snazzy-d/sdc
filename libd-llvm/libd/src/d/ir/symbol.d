module d.ir.symbol;

import d.location;
import d.node;

// XXX: type qualifiers, refactor.
import d.ast.base;
import d.ast.statement;

import d.ir.dscope;
import d.ir.expression;
import d.ir.type;

enum Step {
	Parsed,
	Populated,
	Signed,
	Processed,
}

class Symbol : Node {
	string name;
	string mangle;
	
	import std.bitmanip;
	mixin(bitfields!(
		Visibility, "visibility", 3,
		Linkage, "linkage", 3,
		Step, "step", 2,
		bool, "isStatic", 1,
		bool, "isEnum", 1,
		bool, "isFinal", 1,
		bool, "isAbstract", 1,
		uint, "", 4,
	));
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Symbol that represent a type once resolved.
 */
class TypeSymbol : Symbol {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * Symbol that represent a value once resolved.
 */
// XXX: Store type here ?
class ValueSymbol : Symbol {
	QualType type;
	
	this(Location location, string name, QualType type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Package
 */
class Package : Symbol {
	Package parent;
	
	Scope dscope;
	
	this(Location location, string name, Package parent) {
		super(location, name);
		
		this.parent = parent;
	}
}

/**
 * Variable
 */
class Variable : ValueSymbol {
	Expression value;
	
	this(Location location, QualType type, string name, Expression value) {
		super(location, name, type);
		
		this.value = value;
	}
}

/**
 * Function Declaration
 */
class Function : ValueSymbol {
	string[] paramNames;
	BlockStatement fbody;
	
	NestedScope dscope;
	
	this(Location location, QualType type, string name, string[] paramNames, BlockStatement fbody) {
		super(location, name, type);
		
		this.paramNames = paramNames;
		this.fbody = fbody;
	}
	
	invariant() {
		auto funType = cast(FunctionType) type.type;
		
		assert(funType);
		assert(funType.paramTypes.length == paramNames.length);
	}
}

final:
/**
 * Module
 */
class Module : Package {
	Symbol[] members;
	
	this(Location location, string name, Package parent) {
		super(location, name, parent);
		
		this.parent = parent;
	}
}

/**
 * Alias of types
 */
class TypeAlias : TypeSymbol {
	QualType type;
	
	this(Location location, string name, QualType type) {
		super(location, name);
		
		this.type = type;
	}
}

class Class : TypeSymbol {
	Class base;
	Interface[] interfaces;
	
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, string name, Symbol[] members) {
		super(location, name);
		
		this.name = name;
		this.members = members;
	}
}

class Interface : TypeSymbol {
	Interface[] bases;
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, string name, Interface[] bases, Symbol[] members) {
		super(location, name);
		
		this.bases = bases;
		this.members = members;
	}
}

class Struct : TypeSymbol {
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, string name, Symbol[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Union Declaration
 */
class Union : TypeSymbol {
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, string name, Symbol[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Enum Declaration
 */
class Enum : TypeSymbol {
	Type type;
	
	Scope dscope;
	
	struct Entry {
		string name;
		
		import d.ast.expression;
		CompileTimeExpression value;
	}
	
	Entry[] entries;
	
	this(Location location, string name, Type type, Entry[] entries) {
		super(location, name);
		
		this.type = type;
		this.entries = entries;
	}
}

/**
 * Field
 * Simply a Variable with a field index.
 */
class Field : Variable {
	uint index;
	
	this(Location location, uint index, QualType type, string name, Expression value) {
		super(location, type, name, value);
		
		this.index = index;
	}
	
	this(Variable var, uint index) {
		this(var.location, index, var.type, var.name, var.value);
	}
}

/**
 * Virtual method
 * Simply a function declaration with its index in the vtable.
 */
class Method : Function {
	uint index;
	
	this(Function fun, uint index) {
		super(fun.location, fun.type, fun.name, fun.paramNames, fun.fbody);
		
		this.index = index;
	}
}

