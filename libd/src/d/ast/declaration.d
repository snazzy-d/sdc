module d.ast.declaration;

import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.context.name;
import d.common.node;

/**
 * Any declaration.
 */
class Declaration : Node {
	this(Location location) {
		super(location);
	}
}

struct StorageClass {
	import std.bitmanip;
	mixin(bitfields!(
		TypeQualifier, "qualifier", 3,
		Linkage, "linkage", 3,
		bool, "hasLinkage", 1,
		Visibility, "visibility", 3,
		bool, "hasVisibility", 1,
		bool, "hasQualifier", 1,
		bool, "isRef", 1,
		bool, "isStatic", 1,
		bool, "isEnum", 1,
		bool, "isFinal", 1,
		bool, "isAbstract", 1,
		bool, "isDeprecated", 1,
		bool, "isNoThrow", 1,
		bool, "isOverride", 1,
		bool, "isPure", 1,
		bool, "isSynchronized", 1,
		bool, "isGshared", 1,
		bool, "isProperty", 1,
		bool, "isNoGC", 1,
		uint, "", 7,
	));
}

@property
StorageClass defaultStorageClass() {
	StorageClass stcs;
	stcs.visibility = Visibility.Public;
	
	return stcs;
}

abstract class StorageClassDeclaration : Declaration {
	StorageClass storageClass = defaultStorageClass;
	
	this(Location location, StorageClass storageClass) {
		super(location);
		
		this.storageClass = storageClass;
	}
}

class NamedDeclaration : StorageClassDeclaration {
	Name name;
	
	this(Location location, StorageClass storageClass, Name name) {
		super(location, storageClass);
		
		this.name = name;
	}
}

/**
 * Super class for all templates parameters
 */
class AstTemplateParameter : Declaration {
	Name name;
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
}

final:
/**
 * A D module
 */
class Module : Declaration {
	Name name;
	Name[] packages;
	
	Declaration[] declarations;
	
	this(Location location, Name name, Name[] packages, Declaration[] declarations) {
		super(location);
		
		this.name = name;
		this.packages = packages;
		this.declarations = declarations;
	}
}

/**
 * Identifier alias
 */
class IdentifierAliasDeclaration : NamedDeclaration {
	Identifier identifier;
	
	this(Location location, StorageClass storageClass, Name name, Identifier identifier) {
		super(location, storageClass, name);
		
		this.identifier = identifier;
	}
}

/**
 * Type alias
 */
class TypeAliasDeclaration : NamedDeclaration {
	AstType type;
	
	this(Location location, StorageClass storageClass, Name name, AstType type) {
		super(location, storageClass, name);
		
		this.type = type;
	}
}

/**
 * Value alias
 */
class ValueAliasDeclaration : NamedDeclaration {
	AstExpression value;
	
	this(Location location, StorageClass storageClass, Name name, AstExpression value) {
		super(location, storageClass, name);
		
		this.value = value;
	}
}


/**
 * Alias this
 */
class AliasThisDeclaration : Declaration {
	Name name;
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
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

/**
 * Group of delcarations.
 */
class GroupDeclaration : StorageClassDeclaration {
	Declaration[] declarations;
	
	this(Location location, StorageClass storageClass, Declaration[] declarations) {
		super(location, storageClass);
		
		this.declarations = declarations;
	}
}

/**
 * Variable declaration
 */
class VariableDeclaration : NamedDeclaration {
	AstType type;
	AstExpression value;
	
	this(Location location, StorageClass storageClass, AstType type, Name name, AstExpression value) {
		super(location, storageClass, name);
		
		this.type = type;
		this.value = value;
	}
}

struct ParamDecl {
	Location location;
	ParamAstType type;
	Name name;
	AstExpression value;
	
	this(Location location, ParamAstType type, Name name, AstExpression value) {
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
	
	this(
		Location location,
		StorageClass storageClass,
		ParamAstType returnType,
		Name name,
		ParamDecl[] params,
		bool isVariadic,
		BlockStatement fbody,
	) {
		super(location, storageClass, name);
		
		this.returnType = returnType;
		this.params = params;
		this.isVariadic = isVariadic;
		this.fbody = fbody;
	}
}

/**
 * Template declaration
 */
class TemplateDeclaration : NamedDeclaration {
	AstTemplateParameter[] parameters;
	Declaration[] declarations;
	
	this(Location location, StorageClass storageClass, Name name, AstTemplateParameter[] parameters, Declaration[] declarations) {
		super(location, storageClass, name);
		
		this.parameters = parameters;
		this.declarations = declarations;
	}
}

/**
 * Types templates parameters
 */
class AstTypeTemplateParameter : AstTemplateParameter {
	AstType specialization;
	AstType defaultValue;
	
	this(Location location, Name name, AstType specialization, AstType defaultValue) {
		super(location, name);
		
		this.specialization = specialization;
		this.defaultValue = defaultValue;
	}
}

/**
 * Value template parameters
 */
class AstValueTemplateParameter : AstTemplateParameter {
	AstType type;
	AstExpression defaultValue;
	
	this(Location location, Name name, AstType type, AstExpression defaultValue) {
		super(location, name);
		
		this.type = type;
		this.defaultValue = defaultValue;
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
	AstType type;
	
	this(Location location, Name name, AstType type) {
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
	
	this(Location location, StorageClass storageClass, Name name, Declaration[] members) {
		super(location, storageClass, name);
		
		this.members = members;
	}
}

/**
 * Union Declaration
 */
class UnionDeclaration : NamedDeclaration {
	Declaration[] members;
	
	this(Location location, StorageClass storageClass, Name name, Declaration[] members) {
		super(location, storageClass, name);
		
		this.members = members;
	}
}

/**
 * Class Declaration
 */
class ClassDeclaration : NamedDeclaration {
	Identifier[] bases;
	Declaration[] members;
	
	this(Location location, StorageClass storageClass, Name name, Identifier[] bases, Declaration[] members) {
		super(location, storageClass, name);
		
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
	
	this(Location location, StorageClass storageClass, Name name, Identifier[] bases, Declaration[] members) {
		super(location, storageClass, name);
		
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Enum Declaration
 */
class EnumDeclaration : NamedDeclaration {
	AstType type;
	VariableDeclaration[] entries;
	
	this(Location location, StorageClass storageClass, Name name, AstType type, VariableDeclaration[] entries) {
		super(location, storageClass, name);
		
		this.type = type;
		this.entries = entries;
	}
}

