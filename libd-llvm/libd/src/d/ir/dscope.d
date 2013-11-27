module d.ir.dscope;

import d.ast.base;

import d.ir.symbol;

final class OverloadSet : Symbol {
	Symbol[] set;
	
	this(Location location, Name name, Symbol[] set) {
		super(location, name);
		
		this.set = set;
	}
}

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Module dmodule;
	
	Symbol[Name] symbols;
	
	Module[] imports;
	
	this(Module dmodule) {
		this.dmodule = dmodule;
	}
	
	void addSymbol(Symbol s) {
		assert(!(s.name in symbols), "Already present in scope.");
		
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		auto setPtr = s.name in symbols;
		
		if(setPtr) {
			if(auto set = cast(OverloadSet) *setPtr) {
				set.set ~= s;
				return;
			}
		}
		
		addSymbol(new OverloadSet(s.location, s.name, [s]));
	}
	
	Symbol resolve(Name name) {
		return symbols.get(name, null);
	}
	
	Symbol search(Name name) {
		return resolve(name);
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		super(parent.dmodule);
		
		this.parent = parent;
	}
	
	override Symbol search(Name name) {
		return symbols.get(name, parent.search(name));
	}
	
	final auto clone() {
		auto clone = new NestedScope(parent);
		
		clone.symbols = symbols.dup;
		clone.imports = imports;
		
		return clone;
	}
}

final class SymbolScope : NestedScope {
	Symbol symbol;
	
	this(Symbol symbol, Scope parent) {
		super(parent);
		
		this.symbol = symbol;
	}
}

