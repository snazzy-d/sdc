module d.semantic.aliasthis;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;

import d.context;
import d.exception;
import d.location;

struct AliasThisResolver(alias handler) {
	private SemanticPass pass;
	alias pass this;
	
	alias Ret = typeof(handler(Symbol.init));
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Ret[] resolve(Expression e) {
		auto t = e.type.getCanonical();
		
		import d.ir.type;
		if (!t.isAggregate) {
			return [];
		}

		return resolve(e, t.aggregate);
	}
	
	Ret[] resolve(Expression e, Aggregate a) in {
		assert(e.type.getCanonical().aggregate is a);
	} body {
		return resolve(e, a.dscope.aliasThis);
	}
	
	private Ret[] resolve(Expression e, Name[] aliases) {
		auto oldBuildErrorNode = pass.buildErrorNode;
		scope(exit) pass.buildErrorNode = oldBuildErrorNode;
		
		pass.buildErrorNode = true;
		
		Ret[] results;
		foreach(n; aliases) {
			// XXX: this will swallow error silently.
			// There must be a better way.
			try {
				import d.semantic.identifier;
				results ~= SymbolResolver!handler(pass).resolveInExpression(e.location, e, n);
			} catch(CompileException e) {
				continue;
			}
		}
		
		return results;
	}
}

