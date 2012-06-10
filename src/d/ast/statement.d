module d.ast.statement;

import d.ast.base;

import sdc.location;

class Statement : Node {
	this(Location location) {
		super(location);
	}
}

/**
 * Blocks
 */
class BlockStatement : Statement {
	Statement[] statements;
	
	this(Location location, Statement[] statements) {
		super(location);
		
		this.statements = statements;
	}
}

