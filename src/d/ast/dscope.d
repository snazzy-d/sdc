module d.ast.dscope;

import d.ast.base;
import d.ast.declaration;
import d.ast.dmodule;
import d.ast.identifier;

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Symbol[string] symbols;
	
	Module[] imports;
	
	void addSymbol(Symbol s) {
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		// TODO: handle that properly.
		addSymbol(s);
	}
	
	final Symbol resolve(string name) {
		return symbols.get(name, null);
	}
	
	Symbol search(string name) {
		return resolve(name);
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		this.parent = parent;
	}
	
	override Symbol search(string name) {
		return symbols.get(name, parent.search(name));
	}
}

