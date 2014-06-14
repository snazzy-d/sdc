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
		assert(!s.name.isEmpty, "Symbol can't be added to scope as it has no name.");
		
		if (s.name in symbols) {
			import d.exception;
			throw new CompileException(s.location, "Already in scope");
		}
		
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
		if (typeid(this) !is typeid(NestedScope)) {
			return new NestedScope(this);
		}
		
		auto clone = new NestedScope(parent);
		
		clone.symbols = symbols.dup;
		clone.imports = imports;
		
		return clone;
	}
}

class SymbolScope : NestedScope {
	Symbol symbol;
	
	this(Symbol symbol, Scope parent) {
		super(parent);
		
		this.symbol = symbol;
	}
}

final class ClosureScope : SymbolScope {
	// XXX: Use a proper set :D
	bool[Variable] capture;
	
	this(Symbol symbol, Scope parent) {
		super(symbol, parent);
	}
	
	override Symbol search(Name name) {
		return symbols.get(name, {
			auto s = parent.search(name);
			if (s !is null && typeid(s) is typeid(Variable) && !s.storage.isStatic) {
				capture[() @trusted {
					// Fast cast can be trusted in this case, we already did the check.
					import util.fastcast;
					return fastCast!Variable(s);
				} ()] = true;
				
				s.storage = Storage.Capture;
			}
			
			return s;
		} ());
	}
}

