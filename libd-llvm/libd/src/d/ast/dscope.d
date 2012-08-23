module d.ast.dscope;

import d.ast.declaration;

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
	
	Symbol resolve(string name) {
		return symbols[name];
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		this.parent = parent;
	}
	
	override Symbol resolve(string name) {
		return symbols.get(name, parent.resolve(name));
	}
}

