module d.ir.symbol;

import d.location;
import d.node;

// XXX: type qualifiers, refactor.
import d.ast.base;

import d.ir.dscope;
import d.ir.expression;
import d.ir.statement;
import d.ir.type;

enum Step {
	Parsed,
	Populated,
	Signed,
	Processed,
}

class Symbol : Node {
	Name name;
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
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Symbol that represent a type once resolved.
 */
class TypeSymbol : Symbol {
	this(Location location, Name name) {
		super(location, name);
	}
}

/**
 * Symbol that represent a value once resolved.
 */
// XXX: Store type here ?
class ValueSymbol : Symbol {
	QualType type;
	
	this(Location location, Name name, QualType type) {
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
	
	this(Location location, Name name, Package parent) {
		super(location, name);
		
		this.parent = parent;
	}
}

/**
 * Variable
 */
class Variable : ValueSymbol {
	Expression value;
	
	this(Location location, QualType type, Name name, Expression value = null) {
		super(location, name, type);
		
		this.value = value;
	}
}

/**
 * Function Declaration
 */
class Function : ValueSymbol {
	Parameter[] params;
	BlockStatement fbody;
	
	NestedScope dscope;
	
	this(Location location, QualType type, Name name, Parameter[] params, BlockStatement fbody) {
		super(location, name, type);
		
		this.params = params;
		this.fbody = fbody;
	}
	/+
	// Must disable, access step trigger invariant.
	invariant() {
		if(step > Step.Parsed) {
			auto funType = cast(FunctionType) type.type;
			
			assert(funType);
			assert(funType.paramTypes.length == paramNames.length);
		}
	}
	+/
}

/**
 * Entry for template parameters
 */
class TemplateParameter : Symbol {
	uint index;
	
	this(Location location, Name name, uint index) {
		super(location, name);
		
		this.index = index;
	}
}

final:
/**
 * Module
 */
class Module : Package {
	Symbol[] members;
	
	this(Location location, Name name, Package parent) {
		super(location, name, parent);
	}
}

/**
 * Template
 */
class Template : Symbol {
	TemplateParameter[] parameters;
	
	QualType[] ifti;
	
	import d.ast.declaration;
	Declaration[] members;
	
	Scope dscope;
	
	TemplateInstance[string] instances;
	
	this(Location location, Name name, TemplateParameter[] parameters, Declaration[] members) {
		super(location, name);
		
		this.parameters = parameters;
		this.members = members;
	}
}

/**
 * Template type parameter
 */
class TypeTemplateParameter : TemplateParameter {
	QualType specialization;
	QualType value;
	
	this(Location location, Name name, uint index, QualType specialization, QualType value) {
		super(location, name, index);
		
		this.specialization = specialization;
		this.value = value;
	}
}

/**
* Template instance
*/
class TemplateInstance : Symbol {
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, Template tpl, Symbol[] members) {
		super(location, tpl.name);
		
		this.members = members;
	}
}

/**
 * Alias of types
 */
class TypeAlias : TypeSymbol {
	QualType type;
	
	this(Location location, Name name, QualType type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Class
 */
class Class : TypeSymbol {
	Class base;
	Interface[] interfaces;
	
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, Name name, Symbol[] members) {
		super(location, name);
		
		this.name = name;
		this.members = members;
	}
}

/**
 * Interface
 */
class Interface : TypeSymbol {
	Interface[] bases;
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, Name name, Interface[] bases, Symbol[] members) {
		super(location, name);
		
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Struct
 */
class Struct : TypeSymbol {
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, Name name, Symbol[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Union
 */
class Union : TypeSymbol {
	Symbol[] members;
	
	Scope dscope;
	
	this(Location location, Name name, Symbol[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Enum
 */
class Enum : TypeSymbol {
	Type type;
	
	Scope dscope;
	
	Variable[] entries;
	
	this(Location location, Name name, Type type, Variable[] entries) {
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
	
	this(Location location, uint index, QualType type, Name name, Expression value = null) {
		super(location, type, name, value);
		
		this.index = index;
	}
}

/**
 * function's parameters
 */
class Parameter : ValueSymbol {
	// TODO: remove type from ValueSymbol
	ParamType pt;
	Expression value;
	
	this(Location location, ParamType type, Name name, Expression value) {
		super(location, name, QualType(type.type, type.qualifier));
		
		this.pt = type;
		this.value = value;
	}
}

/**
 * Virtual method
 * Simply a function declaration with its index in the vtable.
 */
class Method : Function {
	uint index;
	
	this(Location location, uint index, QualType type, Name name, Parameter[] params, BlockStatement fbody) {
		super(location, type, name, params, fbody);
		
		this.index = index;
	}
}

