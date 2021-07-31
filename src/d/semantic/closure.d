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
	
	Function visit(Symbol s) in {
		assert(
			s.hasContext,
			"You can't find context of symbol that do not have context"
		);
	} do {
		return this.dispatch(s);
	}
	
	Function visit(Function f) {
		scheduler.require(f, Step.Signed);
		
		// If we have a this pointer, then the context is next.
		auto t = f.type.parameters[0].getType();
		assert(
			t.kind == TypeKind.Context,
			t.toString(context) ~ ": invalid type for a context."
		);
		
		return t.context;
	}
	
	Function visit(SymbolAlias a) {
		return visit(a.symbol);
	}
}
