module d.ast.dscope;

import d.ast.base;
import d.ast.declaration;
import d.ast.dmodule;
import d.ast.identifier;

final class OverLoadSet : Symbol {
	Symbol[] set;
	
	this(Location location, string name, Symbol[] set) {
		super(location, name);
		
		this.set = set;
	}
}

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Symbol[string] symbols;
	
	Module[] imports;
	
	void addSymbol(Symbol s) {
		assert(!(s.name in symbols));
		
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		auto setPtr = s.name in symbols;
		
		if(setPtr) {
			if(auto set = cast(OverLoadSet) *setPtr) {
				set.set ~= s;
				return;
			}
		}
		
		addSymbol(new OverLoadSet(s.location, s.name, [s]));
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
		this.imports = parent.imports;
		
		this.parent = parent;
	}
	
	override Symbol search(string name) {
		return symbols.get(name, parent.search(name));
	}
}

