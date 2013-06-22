module d.ast.dtemplate;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

/**
 * Template declaration
 */
class TemplateDeclaration : NamedDeclaration {
	TemplateParameter[] parameters;
	Declaration[] declarations;
	
	this(Location location, string name, TemplateParameter[] parameters, Declaration[] declarations) {
		super(location, name);
		
		this.parameters = parameters;
		this.declarations = declarations;
	}
}

/**
 * Super class for all templates parameters
 */
class TemplateParameter : NamedDeclaration {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * Types templates parameters
 */
class TypeTemplateParameter : TemplateParameter {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * This templates parameters
 */
class ThisTemplateParameter : TemplateParameter {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * Tuple templates parameters
 */
class TupleTemplateParameter : TemplateParameter {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * Value template parameters
 */
class ValueTemplateParameter : TemplateParameter {
	QualAstType type;
	
	this(Location location, string name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Alias template parameter
 */
class AliasTemplateParameter : TemplateParameter {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * Typed alias template parameter
 */
class TypedAliasTemplateParameter : AliasTemplateParameter {
	QualAstType type;
	
	this(Location location, string name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
}

// XXX: this is an identifier.
/**
 * Template instanciation
 */
class TemplateInstanciation : Node {
	Identifier identifier;
	TemplateArgument[] arguments;
	
	this(Location location, Identifier identifier, TemplateArgument[] arguments) {
		super(location);
		
		this.identifier = identifier;
		this.arguments = arguments;
	}
}

/**
 * Super class for all template arguments.
 */
class TemplateArgument : Node {
	this(Location location) {
		super(location);
	}
}

/**
 * Template type argument
 */
class TypeTemplateArgument : TemplateArgument {
	QualAstType type;
	
	this(Location location, QualAstType type) {
		super(location);
		
		this.type = type;
	}
}
/+
/**
 * Template type argument
 */
class ValueTemplateArgument : TemplateArgument {
	Expression value;
	
	this(Expression value) {
		super(value.location);
		
		this.value = value;
	}
}
+/
/**
 * Template identifier argument
 */
class IdentifierTemplateArgument : TemplateArgument {
	Identifier identifier;
	
	this(Identifier identifier) {
		super(identifier.location);
		
		this.identifier = identifier;
	}
}

