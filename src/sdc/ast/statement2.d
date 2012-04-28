module sdc.ast.statement2;

import sdc.location;
import sdc.ast.base2;

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

