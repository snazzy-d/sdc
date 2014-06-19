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
	Name name;
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Identifier alias
 */
class IdentifierAliasDeclaration : NamedDeclaration {
	Identifier identifier;
	
	this(Location location, Name name, Identifier identifier) {
		super(location, name);
		
		this.identifier = identifier;
	}
}

/**
 * Type alias
 */
class TypeAliasDeclaration : NamedDeclaration {
	QualAstType type;
	
	this(Location location, Name name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Value alias
 */
class ValueAliasDeclaration : NamedDeclaration {
	AstExpression value;
	
	this(Location location, Name name, AstExpression value) {
		super(location, name);
		
		this.value = value;
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
	Name[][] modules;
	
	this(Location location, Name[][] modules) {
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
class VisibilityDeclaration : Declaration {
	Visibility visibility;
	Declaration[] declarations;
	
	this(Location location, Visibility visibility, Declaration[] declarations) {
		super(location);
		
		this.visibility = visibility;
		this.declarations = declarations;
	}
}

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
	Name attribute;
	Declaration[] declarations;
	
	this(Location location, Name attribute, Declaration[] declarations) {
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
	
	bool isEnum = false;
	
	this(Location location, QualAstType type, Name name, AstExpression value) {
		super(location, name);
		
		this.type = type;
		this.value = value;
	}
}

struct ParamDecl {
	Location location;
	ParamAstType type;
	Name name;
	AstExpression value;
	
	this(Location location, ParamAstType type, Name name = Name.init, AstExpression value = null) {
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
	AstBlockStatement fbody;
	
	// XXX: Try to stick that in some pointer.
	bool isVariadic;
	
	this(Location location, Linkage linkage, ParamAstType returnType, Name name, ParamDecl[] params, bool isVariadic, AstBlockStatement fbody) {
		super(location, name);
		
		this.returnType = returnType;
		this.params = params;
		this.fbody = fbody;
		this.isVariadic = isVariadic;
	}
}

/**
 * Template declaration
 */
class TemplateDeclaration : NamedDeclaration {
	AstTemplateParameter[] parameters;
	Declaration[] declarations;
	
	this(Location location, Name name, AstTemplateParameter[] parameters, Declaration[] declarations) {
		super(location, name);
		
		this.parameters = parameters;
		this.declarations = declarations;
	}
}

/**
 * Super class for all templates parameters
 */
class AstTemplateParameter : NamedDeclaration {
	this(Location location, Name name) {
		super(location, name);
	}
}

/**
 * Types templates parameters
 */
class AstTypeTemplateParameter : AstTemplateParameter {
	QualAstType specialization;
	QualAstType defaultValue;
	
	this(Location location, Name name, QualAstType specialization, QualAstType defaultValue) {
		super(location, name);
		
		this.specialization = specialization;
		this.defaultValue = defaultValue;
	}
}

/**
 * Value template parameters
 */
class AstValueTemplateParameter : AstTemplateParameter {
	QualAstType type;
	
	this(Location location, Name name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Alias template parameter
 */
class AstAliasTemplateParameter : AstTemplateParameter {
	this(Location location, Name name) {
		super(location, name);
	}
}

/**
 * Typed alias template parameter
 */
class AstTypedAliasTemplateParameter : AstTemplateParameter {
	QualAstType type;
	
	this(Location location, Name name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * This templates parameters
 */
class AstThisTemplateParameter : AstTemplateParameter {
	this(Location location, Name name) {
		super(location, name);
	}
}

/**
 * Tuple templates parameters
 */
class AstTupleTemplateParameter : AstTemplateParameter {
	this(Location location, Name name) {
		super(location, name);
	}
}

/**
 * Struct Declaration
 */
class StructDeclaration : NamedDeclaration {
	Declaration[] members;
	
	this(Location location, Name name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Union Declaration
 */
class UnionDeclaration : NamedDeclaration {
	Declaration[] members;
	
	this(Location location, Name name, Declaration[] members) {
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
	
	this(Location location, Name name, Identifier[] bases, Declaration[] members) {
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
	
	this(Location location, Name name, Identifier[] bases, Declaration[] members) {
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
	
	this(Location location, Name name, QualAstType type, VariableDeclaration[] entries) {
		super(location, name);
		
		this.type = type;
		this.entries = entries;
	}
}

