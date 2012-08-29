module d.ast.declaration;

import d.ast.base;
import d.ast.expression;
import d.ast.identifier;
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
private class Symbol : Declaration {
	string name;
	string mangling;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
		this.mangling = name;
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
	
	this(VariableDeclaration var, uint index) {
		super(var.location, var.type, var.name, var.value);
		
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
	string name;
	Identifier[] modules;
	
	this(Location location, Identifier[] modules) {
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

