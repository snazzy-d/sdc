module d.ast.dscope;

import d.ast.base;
import d.ast.declaration;
import d.ast.identifier;

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Symbol[string] symbols;
	
	void addSymbol(Symbol s) {
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		// TODO: handle that properly.
		addSymbol(s);
	}
	
	// TODO; refactor that.
	final Symbol resolve(string name) {
		return symbols.get(name, null);
	}
	
	Symbol resolveWithFallback(string name) {
		return resolve(name);
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		this.parent = parent;
	}
	
	override Symbol resolveWithFallback(string name) {
		return symbols.get(name, parent.resolveWithFallback(name));
	}
}

