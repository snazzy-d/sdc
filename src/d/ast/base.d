module d.ast.base;

import sdc.location;

class Node {
	Location location;
	
	this(Location location) {
		this.location = location;
	}
}

