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

class NamedDeclaration : Declaration {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Alias of types
 */
class AliasDeclaration : NamedDeclaration {
	QualAstType type;
	
	this(Location location, string name, QualAstType type) {
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
	Linkage linkage;
	Declaration[] declarations;
	
	this(Location location, Linkage linkage, Declaration[] declarations) {
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
class VariableDeclaration : NamedDeclaration {
	QualAstType type;
	AstExpression value;
	
	this(Location location, QualAstType type, string name, AstExpression value) {
		super(location, name);
		
		this.type = type;
		this.value = value;
	}
}

struct ParamDecl {
	Location location;
	ParamAstType type;
	string name;
	AstExpression value;
	
	this(Location location, ParamAstType type, string name = "", AstExpression value = null) {
		this.location = location;
		this.type = type;
		this.name = name;
		this.value = value;
	}
}

class FunctionDeclaration : NamedDeclaration {
	ParamDecl[] params;
	
	ParamAstType returnType;
	
	import d.ast.statement;
	BlockStatement fbody;
	
	// XXX: Try to stick that in some pointer.
	bool isVariadic;
	
	this(Location location, Linkage linkage, ParamAstType returnType, string name, ParamDecl[] params, bool isVariadic, BlockStatement fbody) {
		super(location, name);
		
		this.returnType = returnType;
		this.params = params;
		this.fbody = fbody;
	}
}















/**
 * Struct Declaration
 */
class StructDeclaration : NamedDeclaration {
	Declaration[] members;
	
	this(Location location, string name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Union Declaration
 */
class UnionDeclaration : NamedDeclaration {
	Declaration[] members;
	
	this(Location location, string name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Class Declaration
 */
class ClassDeclaration : NamedDeclaration {
	Identifier[] bases;
	Declaration[] members;
	
	this(Location location, string name, Identifier[] bases, Declaration[] members) {
		super(location, name);
		
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Interface Declaration
 */
class InterfaceDeclaration : NamedDeclaration {
	Identifier[] bases;
	Declaration[] members;
	
	this(Location location, string name, Identifier[] bases, Declaration[] members) {
		super(location, name);
		
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Enum Declaration
 */
class EnumDeclaration : NamedDeclaration {
	QualAstType type;
	VariableDeclaration[] entries;
	
	this(Location location, string name, QualAstType type, VariableDeclaration[] entries) {
		super(location, name);
		
		this.type = type;
		this.entries = entries;
	}
}

