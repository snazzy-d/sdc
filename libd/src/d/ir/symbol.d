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
	Name mangle;
	
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
	
	string toString(const Context c) const {
		return name.toString(c);
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
class Package : Symbol, Scope {
	mixin ScopeSymbol!(ScopeType.Module);
	
	Package parent;
	
	this(Location location, Name name, Package parent) {
		super(location, name);
		
		this.parent = parent;
	}
}

/**
 * Function
 */
class Function : ValueSymbol, Scope {
	mixin ScopeSymbol;
	FunctionType type;
	
	Variable[] params;
	uint[Variable] closure;
	
	BlockStatement fbody;
	
	this(
		Location location,
		Scope parentScope,
		FunctionType type,
		Name name,
		Variable[] params,
		BlockStatement fbody,
	) {
		super(location, name);
		fillParentScope(parentScope);
		
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
abstract class Aggregate : TypeSymbol, Scope {
	mixin ScopeSymbol;
	Name[] aliasThis;
	
	Symbol[] members;
	
	this(Location location, Scope parentScope, Name name, Symbol[] members) {
		super(location, name);
		fillParentScope(parentScope);
		
		this.members = members;
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
		dmodule = this;
	}
}

/**
 * Variable
 */
class Variable : ValueSymbol {
	Expression value;
	
	ParamType paramType;
	
	this(
		Location location,
		ParamType paramType,
		Name name,
		Expression value = null,
	) {
		super(location, name);
		
		this.paramType = paramType;
		this.value = value;
	}
	
	this(Location location, Type type, Name name, Expression value = null) {
		super(location, name);
		
		this.type = type;
		this.value = value;
	}
	
	@property
	inout(Type) type() inout {
		return paramType.getType();
	}
	
	@property
	Type type(Type t) {
		paramType = t.getParamType(false, false);
		return t;
	}
	
	@property
	bool isRef() const {
		return paramType.isRef;
	}
	
	@property
	bool isFinal() const {
		return paramType.isFinal;
	}
	
	override
	string toString(const Context c) const {
		return type.toString(c) ~ " " ~ name.toString(c)
			~ " = " ~ value.toString(c) ~ ";";
	}
}

/**
 * Field
 * Simply a Variable with a field index.
 */
class Field : ValueSymbol {
	CompileTimeExpression value;
	Type type;
	uint index;
	
	this(
		Location location,
		uint index,
		Type type,
		Name name,
		CompileTimeExpression value = null,
	) {
		super(location, name);
		this.value = value;
		this.type = type;
		this.index = index;
	}
}

/**
 * Template
 */
class Template : Symbol, Scope {
	mixin ScopeSymbol;
	
	TemplateInstance[string] instances;
	Type[] ifti;
	
	TemplateParameter[] parameters;
	
	import d.ast.declaration : Declaration;
	Declaration[] members;
	
	this(
		Location location,
		Scope parentScope,
		Name name,
		TemplateParameter[] parameters,
		Declaration[] members,
	) {
		super(location, name);
		fillParentScope(parentScope);
		
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
	
	this(
		Location location,
		Name name,
		uint index,
		Type specialization,
		Type defaultValue,
	) {
		super(location, name, index);
		
		this.specialization = specialization;
		this.defaultValue = defaultValue;
	}
	
	override string toString(const Context c) const {
		return name.toString(c)
			~ " : " ~ specialization.toString(c)
			~ " = " ~ defaultValue.toString(c);
	}
}

/**
 * Template value parameter
 */
class ValueTemplateParameter : TemplateParameter {
	Type type;
	Expression defaultValue;
	
	this(
		Location location,
		Name name,
		uint index,
		Type type,
		Expression defaultValue,
	) {
		super(location, name, index);
		
		this.type = type;
		this.defaultValue = defaultValue;
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
class TemplateInstance : Symbol, Scope {
	mixin ScopeSymbol!(ScopeType.WithParent, Template);
	
	Symbol[] members;
	
	this(Location location, Template tpl, Symbol[] members) {
		super(location, tpl.name);
		fillParentScope(tpl);
		
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
	
	this(Location location, Scope parentScope, Name name, Symbol[] members) {
		super(location, parentScope, name, members);
		
		this.name = name;
	}
}

/**
 * Interface
 */
class Interface : Aggregate {
	Interface[] bases;
	
	this(
		Location location,
		Scope parentScope,
		Name name,
		Interface[] bases,
		Symbol[] members,
	) {
		super(location, parentScope, name, members);
		this.bases = bases;
	}
}

/**
 * Struct
 */
class Struct : Aggregate {
	this(Location location, Scope parentScope, Name name, Symbol[] members) {
		super(location, parentScope, name, members);
	}
}

/**
 * Union
 */
class Union : Aggregate {
	this(Location location, Scope parentScope, Name name, Symbol[] members) {
		super(location, parentScope, name, members);
	}
}

/**
 * Enum
 */
class Enum : TypeSymbol, Scope {
	mixin ScopeSymbol;
	
	Type type;
	Variable[] entries;
	
	this(
		Location location,
		Scope parentScope,
		Name name,
		Type type,
		Variable[] entries,
	) {
		super(location, name);
		fillParentScope(parentScope);
		
		this.type = type;
		this.entries = entries;
	}
}

/**
 * Virtual method
 * Simply a function declaration with its index in the vtable.
 */
class Method : Function {
	uint index;
	
	this(
		Location location,
		Scope parentScope,
		uint index,
		FunctionType type,
		Name name,
		Variable[] params,
		BlockStatement fbody,
	) {
		super(location, parentScope, type, name, params, fbody);
		
		this.index = index;
	}
}
