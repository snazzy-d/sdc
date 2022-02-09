module d.common.node;

public import source.location;

class Node {
	Location location;

	this(Location location) {
		this.location = location;
	}

	invariant() {
		// FIXME: reenable this when ct paradoxes know their location.
		// assert(location != Location.init, "node location must never be init");
	}

final:
	import source.context;
	auto getFullLocation(Context c) const {
		return location.getFullLocation(c);
	}
}
