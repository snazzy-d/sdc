module sdc.ast.identifier2;

import sdc.location;
import sdc.ast.base : Node;

class Identifier : Node, Qualifier {
	private string name;
	
	this(Location location, string name) {
		this.location = location;
		
		this.name = name;
	}
}

/**
 * Anything that can qualify an identifier
 */
interface Qualifier {
	
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
 * Module qualifier (used for .identifier)
 */
class ModuleQualifier : Node, Qualifier {
	this(Location location) {
		this.location = location;
	}
}

