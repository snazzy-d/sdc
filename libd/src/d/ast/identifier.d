module d.ast.identifier;

import d.ast.declaration;
import d.ast.expression;
import d.ast.type;

import d.context.name;
import d.common.node;

abstract class Identifier : Node {
	Name name;
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
	
	string toString(const Context c) const {
		assert(0, "toString not implement for " ~ typeid(this).toString());
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

final:
/**
 * An identifier.
 */
class BasicIdentifier : Identifier {
	this(Location location, Name name) {
		super(location, name);
	}
	
	override string toString(const Context c) const {
		return name.toString(c);
	}
}

/**
 * An identifier qualified by an identifier (identifier.identifier)
 */
class IdentifierDotIdentifier : Identifier {
	Identifier identifier;
	
	this(Location location, Name name, Identifier identifier) {
		super(location, name);
		
		this.identifier = identifier;
	}
	
	override string toString(const Context c) const {
		return identifier.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * An identifier qualified by a type (type.identifier)
 */
class TypeDotIdentifier : Identifier {
	AstType type;
	
	this(Location location, Name name, AstType type) {
		super(location, name);
		
		this.type = type;
	}
	
	override string toString(const Context c) const {
		return type.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * An identifier qualified by an expression (expression.identifier)
 */
class ExpressionDotIdentifier : Identifier {
	AstExpression expression;
	
	this(Location location, Name name, AstExpression expression) {
		super(location, name);
		
		this.expression = expression;
	}
	
	override string toString(const Context c) const {
		return expression.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * An identifier qualified by a template (template!(...).identifier)
 */
class TemplateInstanciationDotIdentifier : Identifier {
	TemplateInstanciation templateInstanciation;
	
	this(
		Location location,
		Name name,
		TemplateInstanciation templateInstanciation,
	) {
		super(location, name);
		
		this.templateInstanciation = templateInstanciation;
	}
}

/**
 * Template instanciation
 */
class TemplateInstanciation : Node {
	Identifier identifier;
	TemplateArgument[] arguments;
	
	this(
		Location location,
		Identifier identifier,
		TemplateArgument[] arguments,
	) {
		super(location);
		
		this.identifier = identifier;
		this.arguments = arguments;
	}
}

/**
 * Template type argument
 */
class TypeTemplateArgument : TemplateArgument {
	AstType type;
	
	this(Location location, AstType type) {
		super(location);
		
		this.type = type;
	}
}

/**
 * Template value argument
 */
class ValueTemplateArgument : TemplateArgument {
	AstExpression value;
	
	this(AstExpression value) {
		super(value.location);
		
		this.value = value;
	}
}

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

/**
 * A module level identifier (.identifier)
 */
class DotIdentifier : Identifier {
	this(Location location, Name name) {
		super(location, name);
	}
	
	override string toString(const Context c) const {
		return "." ~ name.toString(c);
	}
}

/**
 * An identifier of the form identifier[identifier]
 */
class IdentifierBracketIdentifier : Identifier {
	Identifier indexed;
	Identifier index;
	
	this(Location location, Identifier indexed, Identifier index) {
		super(location, indexed.name);
		
		this.indexed = indexed;
		this.index = index;
	}
	
	override string toString(const Context c) const {
		return indexed.toString(c) ~ "[" ~ index.toString(c) ~ "]";
	}
}

/**
 * An identifier of the form identifier[expression]
 */
class IdentifierBracketExpression : Identifier {
	Identifier indexed;
	AstExpression index;
	
	this(Location location, Identifier indexed, AstExpression index) {
		super(location, indexed.name);
		
		this.indexed = indexed;
		this.index = index;
	}
	
	override string toString(const Context c) const {
		return indexed.toString(c) ~ "[" ~ index.toString(c) ~ "]";
	}
}
