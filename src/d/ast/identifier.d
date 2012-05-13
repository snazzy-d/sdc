module d.ast.identifier;

import d.ast.base;

import sdc.location;

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

