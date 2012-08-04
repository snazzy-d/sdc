module d.ast.identifier;

import d.ast.base;
import d.ast.declaration;
import d.ast.symbol;

class Identifier : Node, Namespace {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
	
	override Symbol resolve(Scope s) {
		assert(0, "resolve not implemented for" ~ typeid(this).toString());
	}
}

/**
 * Anything that can qualify an identifier
 */
interface Namespace {
	Symbol resolve(Scope s);
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
	
	override Symbol resolve(Scope s) {
		assert(0, "resolve not implemented for" ~ typeid(this).toString());
	}
}

