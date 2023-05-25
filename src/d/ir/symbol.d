module d.ir.symbol;

import d.ir.dscope;
import d.ir.expression;
import d.ir.type;

import d.common.node;

import source.context;
import source.name;

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
		// sdfmt off
		Step, "step", 2,
		Linkage, "linkage", 3,
		Visibility, "visibility", 3,
		InTemplate, "inTemplate", 1,
		bool, "hasThis", 1,
		bool, "hasContext", 1,
		bool, "isPoisoned", 1,
		bool, "isAbstract", 1,
		bool, "isFinal", 1,
		bool, "isProperty", 1,
		uint, "__derived", 17,
		// sdfmt on
	));

	this(Location location, Name name) {
		super(location);

		this.name = name;
	}

	string toString(const Context c) const {
		return name.toString(c);
	}

protected:
	@property
	uint derived() const {
		return __derived;
	}

	@property
	uint derived(uint val) {
		__derived = val;
		return derived;
	}
}

/**
 * Symbol that introduce a scope.
 * NB: Symbols that introduce non standard scope may not extend this.
 */
abstract class ScopeSymbol : Symbol, Scope {
	mixin ScopeImpl;

	this(Location location, Scope parentScope, Name name) {
		super(location, name);
		fillParentScope(parentScope);
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
	mixin ScopeImpl!(ScopeType.Module);

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
	mixin ScopeImpl;
	FunctionType type;

	Variable[] params;
	uint[Variable] closure;

	import d.ir.instruction;
	Body fbody;

	this(Location location, Scope parentScope, FunctionType type, Name name,
	     Variable[] params) {
		super(location, name);
		fillParentScope(parentScope);

		this.type = type;
		this.params = params;
	}

	@property
	Intrinsic intrinsicID() const {
		if (hasThis) {
			return Intrinsic.None;
		}

		return cast(Intrinsic) derived;
	}

	@property
	Intrinsic intrinsicID(Intrinsic id) in {
		assert(!hasThis, "Method can't be intrinsic");
		assert(intrinsicID == Intrinsic.None, "This is already an intrinsic");
	} do {
		derived = id;
		return intrinsicID;
	}

	void dump(const Context c) const {
		import std.algorithm, std.range;
		auto params = params.map!(p => p.name.toString(c)).join(", ");

		auto retStr =
			(step >= Step.Signed) ? type.returnType.toString(c) : "__untyped";

		import std.stdio;
		write(retStr, ' ', name.toString(c), '(', params, ") {");
		fbody.dump(c);
		writeln("}\n");
	}
}

/**
 * Entry for template parameters
 */
class TemplateParameter : Symbol {
	this(Location location, Name name, uint index) {
		super(location, name);

		this.derived = index;
	}

final:
	@property
	uint index() const {
		return derived;
	}
}

/**
 * Superclass for struct, class and interface.
 */
abstract class Aggregate : ScopeSymbol {
	Field[] fields;

	Name[] aliasThis;
	Symbol[] members;

	this(Location location, Scope parentScope, Name name) {
		super(location, parentScope, name);
	}
}

final:
/**
 * Module
 */
class Module : Package {
	Symbol[] members;
	Function[] tests;

	this(Location location, Name name, Package parent) {
		super(location, name, parent);
		dmodule = this;
	}
}

/**
 * Placeholder in symbol tables for templates and functions.
 */
class OverloadSet : Symbol {
	Symbol[] set;

	this(Location location, Name name, Symbol[] set) {
		super(location, name);
		this.mangle = name;
		this.set = set;
	}

	OverloadSet clone() {
		auto os = new OverloadSet(location, name, set);
		os.mangle = mangle;
		return os;
	}

	@property
	bool isResolved() const {
		return !!derived;
	}

	@property
	bool isResolved(bool resolved) {
		derived = resolved;
		return resolved;
	}
}

/**
 * Variable
 */
class Variable : ValueSymbol {
	Expression value;
	ParamType paramType;

	this(Location location, ParamType paramType, Name name,
	     Expression value = null) {
		super(location, name);

		this.value = value;
		this.paramType = paramType;
		isFinal = paramType.isFinal;
	}

	this(Location location, Type type, Name name, Expression value = null) {
		super(location, name);

		this.value = value;
		this.type = type;
	}

	@property
	inout(Type) type() inout {
		return paramType.getType();
	}

	@property
	Type type(Type t) {
		paramType = t.getParamType(ParamKind.Regular);
		isFinal = paramType.isFinal;
		return t;
	}

	@property
	bool isRef() const {
		return paramType.isRef;
	}

	@property
	Storage storage() const {
		return cast(Storage) (derived & 0x03);
	}

	@property
	Storage storage(Storage storage) {
		derived = storage;
		return storage;
	}

	override string toString(const Context c) const {
		return type.toString(c) ~ " " ~ name.toString(c) ~ " = "
			~ value.toString(c) ~ ";";
	}
}

/**
 * Field
 * Simply a Variable with a field index.
 */
class Field : ValueSymbol {
	CompileTimeExpression value;
	Type type;

	this(Location location, uint index, Type type, Name name,
	     CompileTimeExpression value = null) {
		super(location, name);

		this.value = value;
		this.type = type;
		this.derived = index;

		// Always true for fields.
		this.hasThis = true;
	}

	@property
	uint index() const {
		return derived;
	}
}

/**
 * Template
 */
class Template : ScopeSymbol {
	TemplateInstance[string] instances;
	Type[] ifti;

	TemplateParameter[] parameters;

	import d.ast.declaration : Declaration;
	Declaration[] members;

	this(Location location, Scope parentScope, Name name,
	     TemplateParameter[] parameters, Declaration[] members) {
		super(location, parentScope, name);

		this.parameters = parameters;
		this.members = members;
	}

	@property
	Storage storage() const {
		return cast(Storage) (derived & 0x03);
	}

	@property
	Storage storage(Storage storage) {
		derived = storage;
		return storage;
	}
}

/**
 * Template type parameter
 */
class TypeTemplateParameter : TemplateParameter {
	Type specialization;
	Type defaultValue;

	this(Location location, Name name, uint index, Type specialization,
	     Type defaultValue) {
		super(location, name, index);

		this.specialization = specialization;
		this.defaultValue = defaultValue;
	}

	override string toString(const Context c) const {
		return name.toString(c) ~ " : " ~ specialization.toString(c) ~ " = "
			~ defaultValue.toString(c);
	}
}

/**
 * Template value parameter
 */
class ValueTemplateParameter : TemplateParameter {
	Type type;
	Expression defaultValue;

	this(Location location, Name name, uint index, Type type,
	     Expression defaultValue) {
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
	mixin ScopeImpl!(ScopeType.WithParent, Template);

	TemplateArgument[] args;
	Symbol[] members;

	this(Location location, Template tpl, TemplateArgument[] args) {
		super(location, tpl.name);
		fillParentScope(tpl);

		this.args = args;
	}

	Template getTemplate() {
		return getParentScope();
	}

	@property
	Storage storage() const {
		return cast(Storage) (derived & 0x03);
	}

	@property
	Storage storage(Storage storage) {
		derived = storage;
		return storage;
	}
}

alias TemplateArgument =
	Type.UnionType!(typeof(null), Symbol, CompileTimeExpression);

auto apply(alias undefinedHandler, alias handler)(TemplateArgument a) {
	alias Tag = typeof(a.tag);
	final switch (a.tag) with (Tag) {
		case Undefined:
			return undefinedHandler();

		case Symbol:
			return handler(a.get!Symbol);

		case CompileTimeExpression:
			return handler(a.get!CompileTimeExpression);

		case Type:
			return handler(a.get!Type);
	}
}

unittest {
	TemplateArgument.init.apply!(() {}, (i) {
		assert(0);
	})();
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
class TypeAlias : Symbol {
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
 * Struct
 */
class Struct : Aggregate {
	this(Location location, Scope parentScope, Name name) {
		super(location, parentScope, name);
	}

	// XXX: std.bitmanip should really offer the possibility to create bitfield
	// out of unused bits of existing bitfields.
	@property
	bool hasIndirection() const
			in(step >= Step.Signed,
			   "Struct need to be signed to use hasIndirection") {
		return !!(derived & 0x01);
	}

	@property
	bool hasIndirection(bool hasIndirection) {
		if (hasIndirection) {
			derived = derived | 0x01;
		} else {
			derived = derived & ~0x01;
		}

		return hasIndirection;
	}

	@property
	bool isPod() const
			in(step >= Step.Signed, "Struct need to be signed to use isPod") {
		return !!(derived & 0x02);
	}

	@property
	bool isPod(bool isPod) {
		if (isPod) {
			derived = derived | 0x02;
		} else {
			derived = derived & ~0x02;
		}

		return isPod;
	}

	@property
	bool isSmall() const
			in(step >= Step.Signed, "Struct need to be signed to use isSmall") {
		return !!(derived & 0x04);
	}

	@property
	bool isSmall(bool isSmall) {
		if (isSmall) {
			derived = derived | 0x04;
		} else {
			derived = derived & ~0x04;
		}

		return isSmall;
	}
}

/**
 * Union
 */
class Union : Aggregate {
	this(Location location, Scope parentScope, Name name) {
		super(location, parentScope, name);
	}

	@property
	bool hasIndirection() const
			in(step >= Step.Signed,
			   "Union need to be signed to use hasIndirection") {
		return !!derived;
	}

	@property
	bool hasIndirection(bool hasIndirection) {
		derived = hasIndirection;
		return hasIndirection;
	}
}

/**
 * Class
 */
class Class : Aggregate {
	Class base;

	Class[] primaries;
	Interface[] interfaces;
	Method[] methods;

	this(Location location, Scope parentScope, Name name) {
		super(location, parentScope, name);

		this.name = name;
	}
}

/**
 * Interface
 */
class Interface : Aggregate {
	Interface[] bases;

	this(Location location, Scope parentScope, Name name, Interface[] bases) {
		super(location, parentScope, name);
		this.bases = bases;
	}
}

/**
 * Enum
 */
class Enum : ScopeSymbol {
	Type type;
	Variable[] entries;

	this(Location location, Scope parentScope, Name name, Type type,
	     Variable[] entries) {
		super(location, parentScope, name);

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

	this(Location location, Scope parentScope, uint index, FunctionType type,
	     Name name, Variable[] params) {
		super(location, parentScope, type, name, params);

		this.index = index;
	}
}
