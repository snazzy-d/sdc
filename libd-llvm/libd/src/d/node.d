module d.node;

import d.location;

class Node {
	Location location;
	
	this(Location location) {
		this.location = location;
	}
	
	invariant() {
		// FIXME: reenable this when ct paradoxes know their location.
		// assert(location != Location.init, "node location must never be init");
	}
}

