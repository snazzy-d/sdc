module d.ast.base;

public import d.location;

class Node {
	Location location;
	
	this(Location location) {
		this.location = location;
		
		// import sdc.terminal;
		// outputCaretDiagnostics(location, typeid(this).toString());
	}
	
	invariant() {
		// FIXME: reenable this when ct paradoxes know their location.
		// assert(location != Location.init, "node location must never be init");
	}
}

