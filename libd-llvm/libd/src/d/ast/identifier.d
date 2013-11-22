module d.ast.identifier;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.type;

abstract class Identifier : Node {
	Name name;
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
	
	final override string toString() {
		const i = this;
		return i.toString();
	}
	
	string toString() const {
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
	/+
	override string toString() const {
		return name;
	}
	+/
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
	/+
	override string toString() const {
		return identifier.toString() ~ "." ~ name;
	}
	+/
}

/**
 * An identifier qualified by a type (type.identifier)
 */
class TypeDotIdentifier : Identifier {
	QualAstType type;
	
	this(Location location, Name name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
	/+
	override string toString() const {
		return type.toString() ~ "." ~ name;
	}
	+/
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
	/+
	override string toString() const {
		return expression.toString() ~ "." ~ name;
	}
	+/
}

/**
 * An identifier qualified by a template (template!(...).identifier)
 */
class TemplateInstanciationDotIdentifier : Identifier {
	TemplateInstanciation templateInstanciation;
	
	this(Location location, Name name, TemplateInstanciation templateInstanciation) {
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
	
	this(Location location, Identifier identifier, TemplateArgument[] arguments) {
		super(location);
		
		this.identifier = identifier;
		this.arguments = arguments;
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
	/+
	override string toString() const {
		return "." ~ name;
	}
	+/
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
	
	override string toString() const {
		return indexed.toString() ~ "[" ~ index.toString() ~ "]";
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
	
	override string toString() const {
		return indexed.toString() ~ "[" ~ index.toString() ~ "]";
	}
}

