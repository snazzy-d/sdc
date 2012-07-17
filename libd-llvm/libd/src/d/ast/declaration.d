module d.ast.declaration;

import d.ast.base;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;
import d.ast.visitor;

enum DeclarationType {
	Variable,
	Function,
	Template,
	TemplateParameter,
	Struct,
	Union,
	Class,
	Enum,
	Alias,
	AliasThis,
	Import,
	Mixin,
	Linkage,
	StorageClass,
	Attribute,
	Visibility,
	Conditional,
}

/**
 * Any declaration is a statement
 */
class Declaration : Statement {
	DeclarationType type;
	
	this(Location location, DeclarationType type) {
		super(location, StatementType.Declaration);
		
		this.type = type;
	}
	
	// TODO: make this abstract
	void accept(DeclarationVisitor) {
		throw new Exception("not implemented");
	}
}

/**
 * Alias of types
 */
class AliasDeclaration : Declaration {
	Type type;
	string name;
	
	this(Location location, string name, Type type) {
		super(location, DeclarationType.Alias);
		
		this.name = name;
		this.type = type;
	}
}

/**
 * Alias this
 */
class AliasThisDeclaration : Declaration {
	Identifier identifier;
	
	this(Location location, Identifier identifier) {
		super(location, DeclarationType.AliasThis);
		
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
		super(location, DeclarationType.Variable);
		
		this.variables = variables;
	}
}

/**
 * Variable declaration
 */
class VariableDeclaration : Declaration {
	Type type;
	string name;
	Expression value;
	
	this(Location location, Type type, string name, Expression value) {
		super(location, DeclarationType.Variable);
		
		this.type = type;
		this.name = name;
		this.value = value;
	}
}

/**
 * Used for type identifier = void;
 */
class VoidInitializer : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Import declaration
 */
class ImportDeclaration : Declaration {
	string name;
	Identifier[] modules;
	
	this(Location location, Identifier[] modules) {
		super(location, DeclarationType.Import);
		
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
		super(location, DeclarationType.StorageClass);
		
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
		super(location, DeclarationType.StorageClass);
		
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
		super(location, DeclarationType.Linkage);
		
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
		super(location, DeclarationType.Attribute);
		
		this.attribute = attribute;
		this.declarations = declarations;
	}
}

