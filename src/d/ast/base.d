module d.ast.base;

public import sdc.location;

class Node {
	Location location;
	
	this(Location location) {
		this.location = location;
	}
	
	invariant() {
		assert(location != Location.init, "node location must never be init");
	}
}

/**
 * Anything an identifier can resolve to.
 */
class Identifiable : Node {
	this(Location location) {
		super(location);
	}
}

