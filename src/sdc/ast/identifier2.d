module sdc.ast.identifier2;

import sdc.location;
import sdc.ast.base : Node;

class Identifier : Node, Namespace {
	private string name;
	
	this(Location location, string name) {
		this.location = location;
		
		this.name = name;
	}
}

/**
 * Anything that can qualify an identifier
 */
interface Namespace {
	
}

/**
 * A qualified identifier (qualifier.identifier)
 */
class QualifiedIdentifier : Identifier {
	private Namespace namespace;
	
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
		this.location = location;
	}
}

