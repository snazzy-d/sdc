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
		Linkage, "linkage", 3,
		Visibility, "visibility", 3,
		Storage, "storage", 2,
		bool, "isAbstract", 1,
		bool, "isProperty", 1,
		bool, "hasThis", 1,
		bool, "hasContext", 1,
		Step, "step", 2,
		uint, "", 2,
	));
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
	
	string toString(Context ctx) const {
		return name.toString(ctx);
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
abstract class ValueSymbol : Symbol {
	this(Location location, Name name) {
		super(location, name);
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
	
	Type type;
	bool isRef;
	bool isFinal;
	
	this(Location location, Type type, Name name, Expression value = null, bool isRef = false, bool isFinal = false) {
		super(location, name);
		
		this.type = type;
		this.value = value;
		this.isRef = isRef;
		this.isFinal = isFinal;
	}
	
	this(Location location, ParamType type, Name name, Expression value = null) {
		super(location, name);
		
		this.type = type.getType();
		this.value = value;
		this.isRef = type.isRef;
		this.isFinal = type.isFinal;
	}
	
final:
	@property
	auto paramType() {
		return type.getParamType(isRef, isFinal);
	}
}

/**
 * Function
 */
class Function : ValueSymbol {
	FunctionType type;
	
	Variable[] params;
	Statement fbody;
	
	FunctionScope dscope;
	
	this(Location location, FunctionType type, Name name, Variable[] params, Statement fbody) {
		super(location, name);
		
		this.type = type;
		this.params = params;
		this.fbody = fbody;
	}
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
 * An Error occured but a Symbol is expected.
 * Useful for speculative compilation.
 */
class ErrorSymbol : Symbol {
	string message;
	
	this(Location location, string message) {
		super(location, BuiltinName!"");
		
		this.message = message;
	}
}

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
	
	Type[] ifti;
	
	import d.ast.declaration;
	Declaration[] members;
	
	SymbolScope dscope;
	
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
	Type specialization;
	Type defaultValue;
	
	this(Location location, Name name, uint index, Type specialization, Type defaultValue) {
		super(location, name, index);
		
		this.specialization = specialization;
		this.defaultValue = defaultValue;
	}
	
	override string toString(Context context) const {
		return name.toString(context) ~ " : " ~ specialization.toString(context) ~ " = " ~ defaultValue.toString(context);
	}
}

/**
 * Template value parameter
 */
class ValueTemplateParameter : TemplateParameter {
	Type type;
	
	this(Location location, Name name, uint index, Type type) {
		super(location, name, index);
		
		this.type = type;
	}
}

/**
 * Template alias parameter
 */
class AliasTemplateParameter : TemplateParameter {
	this(Location location, Name name, uint index) {
		super(location, name, index);
	}
}

/**
 * Template typed alias parameter
 */
class TypedAliasTemplateParameter : TemplateParameter {
	Type type;
	
	this(Location location, Name name, uint index, Type type) {
		super(location, name, index);
		
		this.type = type;
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
 * Alias of symbols
 */
class SymbolAlias : Symbol {
	Symbol symbol;
	
	this(Location location, Name name, Symbol symbol) {
		super(location, name);
		
		this.symbol = symbol;
	}
	/+
	invariant() {
		if (step >= Step.Signed) {
			assert(symbol && hasContext == symbol.hasContext);
		}
	}
	+/
}

/**
 * Alias of types
 */
class TypeAlias : TypeSymbol {
	Type type;
	
	this(Location location, Name name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Alias of values
 */
class ValueAlias : ValueSymbol {
	CompileTimeExpression value;
	
	this(Location location, Name name, CompileTimeExpression value) {
		super(location, name);
		
		this.value = value;
	}
}

/**
 * Class
 */
class Class : TypeSymbol {
	Class base;
	Interface[] interfaces;
	
	Symbol[] members;
	
	AggregateScope dscope;
	
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
	
	AggregateScope dscope;
	
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
	
	AggregateScope dscope;
	
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
	
	SymbolScope dscope;
	
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
	
	SymbolScope dscope;
	
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
	
	this(Location location, uint index, Type type, Name name, Expression value = null) {
		super(location, type, name, value);
		
		this.index = index;
	}
}

/**
 * Virtual method
 * Simply a function declaration with its index in the vtable.
 */
class Method : Function {
	uint index;
	
	this(Location location, uint index, FunctionType type, Name name, Variable[] params, BlockStatement fbody) {
		super(location, type, name, params, fbody);
		
		this.index = index;
	}
}

