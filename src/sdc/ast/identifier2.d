module sdc.ast.identifier2;

import sdc.location;
import sdc.ast.base : Node;

class Identifier : Node {
	private string name;
	
	this(Location location, string name) {
		this.location = location;
		
		this.name = name;
	}
}

/**
 * A qualified identifier (qualifier.identifier)
 */
class QualifiedIdentifier : Identifier {
	private Qualifier qualifier;
	
	this(Location location, string name, Qualifier qualifier) {
		super(location, name);
		
		this.qualifier = qualifier;
	}
}

/**
 * Anything that can qualify an identifier
 */
interface Qualifier {
	
}

/**
 * An identifier used as qualifier
 */
class IdentifierQualifier : Node, Qualifier {
	private Identifier qualifier;
	
	this(Location location, Identifier qualifier) {
		this.location = location;
		
		this.qualifier = qualifier;
	}
}

