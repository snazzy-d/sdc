module d.ast.identifier;

import d.ast.ambiguous;
import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.type;

class Identifier : Node {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
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
}

/**
 * An identifier qualified by a type (type.identifier)
 */
class TypeDotIdentifier : Identifier {
	Type type;
	
	this(Location location, string name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

/**
 * An identifier qualified by an expression (expression.identifier)
 */
class ExpressionDotIdentifier : Identifier {
	Expression expression;
	
	this(Location location, string name, Expression expression) {
		super(location, name);
		
		this.expression = expression;
	}
}

/**
 * An identifier qualified by an expression or a type (ambyguous.identifier)
 */
class AmbiguousDotIdentifier : Identifier {
	TypeOrExpression qualifier;
	
	this(Location location, string name, TypeOrExpression qualifier) {
		super(location, name);
		
		this.qualifier = qualifier;
	}
}

/**
 * A module level identifier (.identifier)
 */
class DotIdentifier : Identifier {
	this(Location location, string name) {
		super(location, name);
	}
}

