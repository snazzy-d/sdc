module d.ast.dtemplate;

import d.ast.ambiguous;
import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

/**
 * Template declaration
 */
class TemplateDeclaration : Symbol {
	TemplateParameter[] parameters;
	Declaration[] declarations;
	
	Scope parentScope;
	
	TemplateInstance[] instances;
	
	this(Location location, string name, TemplateParameter[] parameters, Declaration[] declarations) {
		super(location, name);
		
		this.parameters = parameters;
		this.declarations = declarations;
	}
}

/**
 * Super class for all templates parameters
 */
class TemplateParameter : TypeSymbol {
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
	Type type;
	
	this(Location location, string name, Type type) {
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
	Type type;
	
	this(Location location, string name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

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
 * Template instance
 */
// XXX: Is it really identifiable ? Seems like we have a better design decision to make here.
class TemplateInstance : Identifiable {
	TemplateArgument[] arguments;
	Declaration[] declarations;
	
	Scope dscope;
	
	this(Location location, TemplateArgument[] arguments, Declaration[] declarations) {
		super(location);
		
		this.arguments = arguments;
		this.declarations = declarations;
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

