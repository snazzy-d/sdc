module sdc.ast.expression2;

import sdc.location;
import sdc.ast.statement2;

class Expression : Statement {
	this(Location location) {
		super(location);
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
 * || and &&
 */
class LogicalBinaryExpression : BinaryExpression {
	this(Location location, Expression lhs, Expression rhs) {
		super(location, lhs, rhs);
	}
}

