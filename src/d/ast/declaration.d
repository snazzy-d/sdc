module d.ast.declaration;

import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

import sdc.location;

enum DeclarationType {
	Variable,
	Function,
	Template,
	TemplateParameter,
	Struct,
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
		super(location);
		
		this.type = type;
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

/**
 * Variables declaration
 */
class VariablesDeclaration : Declaration {
	Type type;
	Expression[string] variables;
	
	this(Location location, Expression[string] variables, Type type) {
		super(location, DeclarationType.Variable);
		
		this.type = type;
		this.variables = variables;
	}
}

/**
 * Function Declaration
 */
class FunctionDeclaration : Declaration {
	string name;
	Type returnType;
	Parameter[] parameters;
	
	this(Location location, string name, Type returnType, Parameter[] parameters) {
		super(location, DeclarationType.Function);
		
		this.name = name;
		this.returnType = returnType;
		this.parameters = parameters;
	}
}

/**
 * Function Definition
 */
class FunctionDefinition : FunctionDeclaration {
	Statement fbody;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, Statement fbody) {
		super(location, name, returnType, parameters);
		
		this.fbody = fbody;
	}
}

/**
 * Constructor Declaration
 */
class ConstructorDeclaration : Declaration {
	Parameter[] parameters;
	
	this(Location location, Parameter[] parameters) {
		super(location, DeclarationType.Function);
		
		this.parameters = parameters;
	}
}

/**
 * Constructor Definition
 */
class ConstructorDefinition : ConstructorDeclaration {
	Statement fbody;
	
	this(Location location, Parameter[] parameters, Statement fbody) {
		super(location, parameters);
		
		this.fbody = fbody;
	}
}

/**
 * Destructor Declaration
 */
class DestructorDeclaration : Declaration {
	Parameter[] parameters;
	
	this(Location location, Parameter[] parameters) {
		super(location, DeclarationType.Function);
		
		this.parameters = parameters;
	}
}

/**
 * Destructor Definition
 */
class DestructorDefinition : DestructorDeclaration {
	Statement fbody;
	
	this(Location location, Parameter[] parameters, Statement fbody) {
		super(location, parameters);
		
		this.fbody = fbody;
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

