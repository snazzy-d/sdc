module d.semantic.closure;

import d.semantic.semantic;

import d.ir.symbol;
import d.ir.type;

struct ContextFinder {
	private SemanticPass pass;
	alias pass this;

	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	ContextType visit(Symbol s) in {
		assert(s.hasContext, "You can't find context of symbol that do not have context.");
	} body {
		return this.dispatch(s);
	}
	
	ContextType visit(Function f) {
		scheduler.require(f, Step.Signed);
		
		// If we have a this pointer, then the context is next.
		auto type = cast(ContextType) (f.type.paramTypes[f.hasThis].type);
		assert(type, typeid(type).toString() ~ ": invalid type for a context.");
		
		return type;
	}
	
	ContextType visit(SymbolAlias a) {
		return visit(a.symbol);
	}
}

