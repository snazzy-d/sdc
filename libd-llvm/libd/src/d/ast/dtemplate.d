module d.ast.dtemplate;

import d.ast.ambiguous;
import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

/**
 * Template declaration
 */
class TemplateDeclaration : Symbol {
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
class TemplateParameter : Declaration {
	this(Location location) {
		super(location);
	}
}

/**
 * Types templates parameters
 */
class TypeTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * This templates parameters
 */
class ThisTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Tuple templates parameters
 */
class TupleTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Value template parameters
 */
class ValueTemplateParameter : TemplateParameter {
	string name;
	Type type;
	
	this(Location location, string name, Type type) {
		super(location);
		
		this.name = name;
		this.type = type;
	}
}

/**
 * Alias template parameter
 */
class AliasTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Typed alias template parameter
 */
class TypedAliasTemplateParameter : AliasTemplateParameter {
	Type type;
	
	this(Location location, string name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * Template instance
 */
class TemplateInstance : Identifier {
	Identifier identifier;
	
	TemplateArgument[] arguments;
	
	this(Location location, Identifier identifier, TemplateArgument[] arguments) {
		// Eponymous trick.
		super(location, identifier.name);
		
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
	Type type;
	
	this(Type type) {
		super(type.location);
		
		this.type = type;
	}
}

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

/**
 * Template type argument
 */
class AmbiguousTemplateArgument : TemplateArgument {
	TypeOrExpression parameter;
	
	this(TypeOrExpression parameter) {
		super(parameter.location);
		
		this.parameter = parameter;
	}
}

