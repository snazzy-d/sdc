module d.ast.identifier;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;

class Identifier : Node, Namespace {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
	
	override Namespace resolve(Location location, string name) {
		assert(0, "resolve is not implemented for namespace " ~ typeid(this).toString() ~ ".");
	}
}

/**
 * Anything that can qualify an identifier
 */
interface Namespace {
	Namespace resolve(Location location, string name);
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
	
	override Symbol resolve(Location location, string name) {
		assert(0, "resolve is not implemented for namespace " ~ typeid(this).toString() ~ ".");
	}
}

