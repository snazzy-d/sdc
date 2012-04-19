module sdc.ast.identifier2;

import sdc.location;
import sdc.ast.base2;

class Identifier : Node, Namespace {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Anything that can qualify an identifier
 */
interface Namespace {
	
}

/**
 * A qualified identifier (namespace.identifier)
 */
class QualifiedIdentifier : Identifier {
	Namespace namespace;
	
	this(Location location, string name, Namespace namespace) {
		super(location, name);
		
		this.namespace = namespace;
	}
}

/**
 * Module qualifier (used for .identifier)
 */
class ModuleNamespace : Node, Namespace {
	this(Location location) {
		super(location);
	}
}

