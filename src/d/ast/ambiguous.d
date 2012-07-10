module d.ast.ambiguous;

import d.ast.base;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

class TypeOrExpression : Node, Namespace {
	Type type;
	Expression expression;
	
	this(Type type, Expression expression) in {
		assert(type.location == expression.location, "type and expression must represent parsing of the same source code.");
	} body {
		super(type.location);
		
		this.type = type;
		this.expression = expression;
	}
}

