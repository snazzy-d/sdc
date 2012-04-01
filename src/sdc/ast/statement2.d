module sdc.ast.statement2;

import sdc.location;
import sdc.ast.base;

class Statement : Node {
	this(Location location) {
		this.location = location;
	}
}

