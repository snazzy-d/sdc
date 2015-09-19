module d.ir.symbol;

import d.ir.dscope;
import d.ir.expression;
import d.ir.statement;
import d.ir.type;

import d.context.name;
import d.common.node;

public import d.common.qualifier;

enum Step {
	Parsed,
	Populated,
	Signed,
	Processed,
}

enum InTemplate {
	No,
	Yes,
}

class Symbol : Node {
	Name name;
	string mangle;
	
	import std.bitmanip;
	mixin(bitfields!(
		Step, "step", 2,
		Linkage, "linkage", 3,
		Visibility, "visibility", 3,
		Storage, "storage", 2,
		InTemplate, "inTemplate", 1,
		bool, "isAbstract", 1,
		bool, "isProperty", 1,
		bool, "hasThis", 1,
		bool, "hasContext", 1,
		uint, "", 1,
	));
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
	
	string toString(const ref NameManager nm) const {
		return name.toString(nm);
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
	
	ParamType paramType;
	
	this(Location location, ParamType paramType, Name name, Expression value = null) {
		super(location, name);
		
		this.paramType = paramType;
		this.value = value;
	}
	
	this(Location location, Type type, Name name, Expression value = null) {
		this(location, type.getParamType(false, false), name, value);
	}
	
final:
	@property
	Type type() {
		return paramType.getType();
	}
	
	@property
	bool isRef() {
		return paramType.isRef;
	}
	
	@property
	bool isFinal() {
		return paramType.isFinal;
	}
}

/**
 * Function
 */
class Function : ValueSymbol {
	FunctionType type;
	
	Variable[] params;
	BlockStatement fbody;
	
	FunctionScope dscope;

	uint[Variable] closure;
	
	this(Location location, FunctionType type, Name name, Variable[] params, BlockStatement fbody) {
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

/**
 * Superclass for struct, class and interface.
 */
abstract class Aggregate : TypeSymbol {
	Symbol[] members;
	
	AggregateScope dscope;
	
	this(Location location, Name name, Symbol[] members) {
		super(location, name);
		
		this.members = members;
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
		step = Step.Processed;
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
	
	override string toString(const ref NameManager nm) const {
		return name.toString(nm) ~ " : " ~ specialization.toString(nm) ~ " = " ~ defaultValue.toString(nm);
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
class Class : Aggregate {
	Class base;
	Interface[] interfaces;
	
	this(Location location, Name name, Symbol[] members) {
		super(location, name, members);
		
		this.name = name;
	}
}

/**
 * Interface
 */
class Interface : Aggregate {
	Interface[] bases;
	
	this(Location location, Name name, Interface[] bases, Symbol[] members) {
		super(location, name, members);
		this.bases = bases;
	}
}

/**
 * Struct
 */
class Struct : Aggregate {
	this(Location location, Name name, Symbol[] members) {
		super(location, name, members);
	}
}

/**
 * Union
 */
class Union : Aggregate {
	this(Location location, Name name, Symbol[] members) {
		super(location, name, members);
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
	
	this(Location location, uint index, ParamType paramType, Name name, Expression value = null) {
		super(location, paramType, name, value);
		this.index = index;
	}
	
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
