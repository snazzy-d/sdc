module d.ast.identifier;

import d.ast.base;
import d.ast.declaration;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

abstract class Identifier : Node {
	string name;
	
	this(Location location, string name) {
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

final:
/**
 * An identifier.
 */
class BasicIdentifier : Identifier {
	this(Location location, string name) {
		super(location, name);
	}
	
	override string toString() const {
		return name;
	}
}

/**
 * An identifier qualified by an identifier (identifier.identifier)
 */
class IdentifierDotIdentifier : Identifier {
	Identifier identifier;
	
	this(Location location, string name, Identifier identifier) {
		super(location, name);
		
		this.identifier = identifier;
	}
	
	override string toString() const {
		return identifier.toString() ~ "." ~ name;
	}
}

/**
 * An identifier qualified by a type (type.identifier)
 */
class TypeDotIdentifier : Identifier {
	QualAstType type;
	
	this(Location location, string name, QualAstType type) {
		super(location, name);
		
		this.type = type;
	}
	
	override string toString() const {
		return type.toString() ~ "." ~ name;
	}
}

/**
 * An identifier qualified by an expression (expression.identifier)
 */
class ExpressionDotIdentifier : Identifier {
	AstExpression expression;
	
	this(Location location, string name, AstExpression expression) {
		super(location, name);
		
		this.expression = expression;
	}
	
	override string toString() const {
		return expression.toString() ~ "." ~ name;
	}
}

/**
 * An identifier qualified by a template (template!(...).identifier)
 */
class TemplateInstanciationDotIdentifier : Identifier {
	TemplateInstanciation templateInstanciation;
	
	this(Location location, string name, TemplateInstanciation templateInstanciation) {
		super(location, name);
		
		this.templateInstanciation = templateInstanciation;
	}
}

/**
 * A module level identifier (.identifier)
 */
class DotIdentifier : Identifier {
	this(Location location, string name) {
		super(location, name);
	}
	
	override string toString() const {
		return "." ~ name;
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

