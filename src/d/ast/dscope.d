module d.ast.dscope;

import d.ast.base;
import d.ast.declaration;
import d.ast.identifier;

/**
 * A scope associate identifier with declarations.
 */
class Scope : Namespace {
	Symbol[string] symbols;
	
	void addSymbol(Symbol s) {
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		// TODO: handle that properly.
		addSymbol(s);
	}
	
	// TODO; refactor that.
	final Symbol resolve(Location location, string name) {
		return symbols[name];
	}
	
	Symbol resolveWithFallback(Location location, string name) {
		return symbols[name];
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		this.parent = parent;
	}
	
	override Symbol resolveWithFallback(Location location, string name) {
		return symbols.get(name, parent.resolveWithFallback(location, name));
	}
}

