module d.ast.declaration;

import d.ast.base;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

/**
 * Any declaration.
 */
class Declaration : Node {
	this(Location location) {
		super(location);
	}
}

/**
 * A declaration that introduce a new symbol.
 * Nothing inherit directly from Symbol.
 * It is either a TypeSymbol or an ExpressionSymbol.
 */
class Symbol : Declaration {
	string name;
	string linkage;
	string mangle;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
		this.mangle = name;
	}
}

/**
 * A Symbol that is a type.
 */
class TypeSymbol : Symbol {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * A Symbol that is an expression.
 */
class ExpressionSymbol : Symbol {
	Type type;
	bool isStatic;
	bool isEnum;
	
	this(Location location, string name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Alias of types
 */
class AliasDeclaration : TypeSymbol {
	Type type;
	
	this(Location location, string name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Alias this
 */
class AliasThisDeclaration : Declaration {
	Identifier identifier;
	
	this(Location location, Identifier identifier) {
		super(location);
		
		this.identifier = identifier;
	}
}

// TODO: create declaration aggregate and merge that in it.
/**
 * Variables declaration
 */
class VariablesDeclaration : Declaration {
	VariableDeclaration[] variables;
	
	this(Location location, VariableDeclaration[] variables) {
		super(location);
		
		this.variables = variables;
	}
}

/**
 * Variable declaration
 */
class VariableDeclaration : ExpressionSymbol {
	Expression value;
	
	this(Location location, Type type, string name, Expression value) {
		super(location, name, type);
		
		this.value = value;
	}
}

/**
 * Field declaration.
 * Simply a variable declaration with a field index.
 */
class FieldDeclaration : VariableDeclaration {
	uint index;
	
	this(Location location, uint index, Type type, string name, Expression value) {
		super(location, type, name, value);
		
		this.index = index;
	}
	
	this(VariableDeclaration var, uint index) {
		this(var.location, index, var.type, var.name, var.value);
	}
}

/**
 * Function Declaration
 */
class FunctionDeclaration : ExpressionSymbol {
	Type returnType;		// TODO: remove this, redundant information.
	Parameter[] parameters;
	bool isVariadic;
	BlockStatement fbody;
	
	import d.ast.dscope;
	NestedScope dscope;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, bool isVariadic, BlockStatement fbody) {
		this(location, name, "D", returnType, parameters, isVariadic, fbody);
	}
	
	this(Location location, string name, string linkage, Type returnType, Parameter[] parameters, bool isVariadic, BlockStatement fbody) {
		super(location, name, new FunctionType(location, linkage, returnType, parameters, isVariadic));
		
		this.name = name;
		this.linkage = linkage;
		this.returnType = returnType;
		this.parameters = parameters;
		this.isVariadic = isVariadic;
		this.fbody = fbody;
	}
	/*
	invariant() {
		auto funType = cast(FunctionType) type;
		
		assert(funType && funType.linkage == linkage);
	}
	*/
}

/**
 * Virtual method declaration.
 * Simply a function declaration with its index in the vtable.
 */
class MethodDeclaration : FunctionDeclaration {
	uint index;
	
	this(FunctionDeclaration fun, uint index) {
		super(fun.location, fun.name, fun.linkage, fun.returnType, fun.parameters, fun.isVariadic, fun.fbody);
		
		this.index = index;
	}
}

/**
 * Used for type identifier;
 */
class DefaultInitializer : Expression {
	this(Type type) {
		super(type.location, type);
	}
}

/**
 * Used for type identifier = void;
 */
class VoidInitializer : Expression {
	this(Location location, Type type) {
		super(location, type);
	}
}

/**
 * Import declaration
 */
class ImportDeclaration : Declaration {
	string[][] modules;
	
	this(Location location, string[][] modules) {
		super(location);
		
		this.modules = modules;
	}
}

enum StorageClass {
	Const,
	Immutable,
	Inout,
	Shared,
	Abstract,
	Deprecated,
	Nothrow,
	Override,
	Pure,
	Static,
	Synchronized,
	__Gshared,
}

/**
 * Storage class declaration
 */
class StorageClassDeclaration(StorageClass storageClass) : Declaration {
	Declaration[] declarations;
	
	this(Location location, Declaration[] declarations) {
		super(location);
		
		this.declarations = declarations;
	}
}

alias StorageClassDeclaration!(StorageClass.Const) ConstDeclaration;
alias StorageClassDeclaration!(StorageClass.Immutable) ImmutableDeclaration;
alias StorageClassDeclaration!(StorageClass.Inout) InoutDeclaration;
alias StorageClassDeclaration!(StorageClass.Shared) SharedDeclaration;
alias StorageClassDeclaration!(StorageClass.Abstract) AbstractDeclaration;
alias StorageClassDeclaration!(StorageClass.Deprecated) DeprecatedDeclaration;
alias StorageClassDeclaration!(StorageClass.Nothrow) NothrowDeclaration;
alias StorageClassDeclaration!(StorageClass.Override) OverrideDeclaration;
alias StorageClassDeclaration!(StorageClass.Pure) PureDeclaration;
alias StorageClassDeclaration!(StorageClass.Static) StaticDeclaration;
alias StorageClassDeclaration!(StorageClass.Synchronized) SynchronizedDeclaration;
alias StorageClassDeclaration!(StorageClass.__Gshared) __GsharedDeclaration;

enum Visibility {
	Public,
	Private,
	Protected,
	Package,
	Export,
}

/**
 * Visibility class declaration
 */
class VisibilityDeclaration(Visibility visibility) : Declaration {
	Declaration[] declarations;
	
	this(Location location, Declaration[] declarations) {
		super(location);
		
		this.declarations = declarations;
	}
}

alias VisibilityDeclaration!(Visibility.Public) PublicDeclaration;
alias VisibilityDeclaration!(Visibility.Private) PrivateDeclaration;
alias VisibilityDeclaration!(Visibility.Protected) ProtectedDeclaration;
alias VisibilityDeclaration!(Visibility.Package) PackageDeclaration;
alias VisibilityDeclaration!(Visibility.Export) ExportDeclaration;

/**
 * Linkage declaration
 */
class LinkageDeclaration : Declaration {
	string linkage;
	Declaration[] declarations;
	
	this(Location location, string linkage, Declaration[] declarations) {
		super(location);
		
		this.linkage = linkage;
		this.declarations = declarations;
	}
}

/**
 * Attribute declaration
 */
class AttributeDeclaration : Declaration {
	string attribute;
	Declaration[] declarations;
	
	this(Location location, string attribute, Declaration[] declarations) {
		super(location);
		
		this.attribute = attribute;
		this.declarations = declarations;
	}
}

