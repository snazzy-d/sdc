module sdc.ast.expression2;

import sdc.location;
import sdc.ast.base;

class Expression : Node {
	this(Location location) {
		this.location = location;
	}
}

class BinaryExpression : Expression {
	private Expression lhs;
	private Expression rhs;
	
	this(Location location, Expression lhs, Expression rhs) {
		super(location);
		
		this.lhs = lhs;
		this.rhs = rhs;
	}
}

/**
 * For || and &&
 */
class LogicalBinaryExpression : BinaryExpression {
	this(Location location, Expression lhs, Expression rhs) {
		super(location, lhs, rhs);
	}
}

