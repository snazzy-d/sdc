module d.ir.dscope;

import d.ir.symbol;

import d.ast.conditional;

import d.context.location;
import d.context.name;

// XXX: move this to a more apropriate place ?
final class OverloadSet : Symbol {
	Symbol[] set;
	bool isPoisoned;
	
	this(Location location, Name name, Symbol[] set) {
		super(location, name);
		this.set = set;
	}
}

struct ConditionalBranch {
	// XXX: stick that bit in the pointer.
	StaticIfDeclaration sif;
	bool branch;
}

/**
 * A scope associate identifier with declarations.
 */
class Scope {
	Module dmodule;
	
	Symbol[Name] symbols;
	
	Module[] imports;
	
	private bool isPoisoning;
	private bool isPoisoned;
	private bool hasConditional;
	
	this(Module dmodule) {
		this.dmodule = dmodule;
	}
	
	Symbol search(Name name) {
		return resolve(name);
	}
	
final:
	Symbol resolve(Name name) {
		if (auto sPtr = name in symbols) {
			auto s = *sPtr;
			if (isPoisoning) {
				if (auto os = cast(OverloadSet) s) {
					os.isPoisoned = true;
				} else if (isPoisoned && cast(Poison) s) {
					return null;
				} else if (hasConditional) {
					if (auto cs = cast(ConditionalSet) s) {
						cs.isPoisoned = true;
						return cs.selected;
					}
				}
			}
			
			return s;
		}
		
		if (isPoisoning) {
			symbols[name] = new Poison(name);
			isPoisoned = true;
		}
		
		return null;
	}
	
	void addSymbol(Symbol s) {
		assert(!s.name.isEmpty, "Symbol can't be added to scope as it has no name.");
		
		if (auto sPtr = s.name in symbols) {
			if(auto p = cast(Poison) *sPtr) {
				import d.exception;
				throw new CompileException(s.location, "Poisoned");
			}
			
			import d.exception;
			throw new CompileException(s.location, "Already defined");
		}
		
		symbols[s.name] = s;
	}
	
	void addOverloadableSymbol(Symbol s) {
		if(auto sPtr = s.name in symbols) {
			if(auto os = cast(OverloadSet) *sPtr) {
				if (os.isPoisoned) {
					import d.exception;
					throw new CompileException(s.location, "Poisoned");
				}
				
				os.set ~= s;
				return;
			}
		}
		
		addSymbol(new OverloadSet(s.location, s.name, [s]));
	}
	
	void addConditionalSymbol(Symbol s, ConditionalBranch[] cdBranches) in {
		assert(cdBranches.length > 0, "No conditional branches supplied");
	} body {
		auto entry = ConditionalEntry(s, cdBranches);
		if (auto csPtr = s.name in symbols) {
			if(auto cs = cast(ConditionalSet) *csPtr) {
				cs.set ~= entry;
				return;
			}
			
			import d.exception;
			throw new CompileException(s.location, "Already defined");
		}
		
		symbols[s.name] = new ConditionalSet(s.location, s.name, [entry]);
		hasConditional = true;
	}
	
	// XXX: Use of smarter data structure can probably improve things here :D
	void resolveConditional(StaticIfDeclaration sif, bool branch) in {
		assert(isPoisoning, "You must be in poisoning mode when resolving static ifs.");
	} body {
		foreach(s; symbols.values) {
			if(auto cs = cast(ConditionalSet) s) {
				ConditionalEntry[] newSet;
				foreach(cd; cs.set) {
					if(cd.cdBranches[0].sif is sif) {
						// If this the right branch, then proceed. Otherwize forget.
						if(cd.cdBranches[0].branch == branch) {
							cd.cdBranches = cd.cdBranches[1 .. $];
							if(cd.cdBranches.length) {
								newSet ~= cd;
							} else {
								// FIXME: Check if it is an overloadable symbol.
								assert(cs.selected is null, "overload ? bug ?");
								if (cs.isPoisoned) {
									import d.exception;
									throw new CompileException(s.location, "Poisoned");
								}

								cs.selected = cd.entry;
							}
						}
					} else {
						newSet ~= cd;
					}
				}
				
				cs.set = newSet;
			}
		}
	}
	
	void setPoisoningMode() in {
		assert(isPoisoning == false, "poisoning mode is already on.");
	} body {
		isPoisoning = true;
	}
	
	void clearPoisoningMode() in {
		assert(isPoisoning == true, "poisoning mode is not on.");
	} body {
		// XXX: Consider not removing tags on OverloadSet.
		// That would allow to not pass over the AA most of the time.
		foreach(n; symbols.keys) {
			auto s = symbols[n];
			if (auto os = cast(OverloadSet) s) {
				os.isPoisoned = false;
			} else if(isPoisoned && cast(Poison) s) {
				symbols.remove(n);
			} else if (hasConditional) {
				if (auto cs = cast(ConditionalSet) s) {
					assert(cs.set.length == 0, "Conditional symbols remains when clearing poisoning mode.");
					if (cs.selected) {
						symbols[n] = cs.selected;
					} else {
						symbols.remove(n);
					}
				}
			}
		}
		
		isPoisoning = false;
		isPoisoned = false;
		hasConditional = false;
	}
}

class NestedScope : Scope {
	Scope parent;
	
	this(Scope parent) {
		super(parent.dmodule);
		this.parent = parent;
	}
	
	override Symbol search(Name name) {
		if (auto s = resolve(name)) {
			return s;
		}
		
		return parent.search(name);
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

// XXX: Find a way to get a better handling of the symbol's type.
class SymbolScope : NestedScope {
	Symbol symbol;
	
	this(Symbol symbol, Scope parent) {
		super(parent);
		this.symbol = symbol;
	}
}

class AggregateScope : SymbolScope {
	Name[] aliasThis;

	this(Symbol symbol, Scope parent) {
		super(symbol, parent);
	}
}

alias FunctionScope  = SymbolScope;

alias ClosureScope   = CapturingScope!FunctionScope;
alias VoldemortScope = CapturingScope!AggregateScope;

private:

final:
class CapturingScope(S) : S  if(is(S : SymbolScope)){
	// XXX: Use a proper set :D
	bool[Variable] capture;
	
	this(Symbol symbol, Scope parent) {
		super(symbol, parent);
	}
	
	override Symbol search(Name name) {
		if (auto s = resolve(name)) {
			return s;
		}
		
		auto s = parent.search(name);

		import d.common.qualifier;
		if (s !is null && typeid(s) is typeid(Variable) && !s.storage.isNonLocal) {
			capture[() @trusted {
				// Fast cast can be trusted in this case, we already did the check.
				import util.fastcast;
				return fastCast!Variable(s);
			} ()] = true;
			
			s.storage = Storage.Capture;
		}
		
		return s;
	}
}

class Poison : Symbol {
	this(Location location, Name name) {
		super(location, name);
	}
	
	this(Name name) {
		super(Location.init, name);
	}
}

struct ConditionalEntry {
	Symbol entry;
	ConditionalBranch[] cdBranches;
}

class ConditionalSet : Symbol {
	ConditionalEntry[] set;
	
	Symbol selected;
	bool isPoisoned;
	
	this(Location location, Name name, ConditionalEntry[] set) {
		super(location, name);
		this.set = set;
	}
}

