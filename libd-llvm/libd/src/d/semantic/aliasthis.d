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
		if (t.kind == TypeKind.Struct) {
			return resolve(e, t.dstruct);
		} else if (t.kind == TypeKind.Class) {
			return resolve(e, t.dclass);
		}
		
		return [];
	}
	
	Ret[] resolve(Expression e, Struct s) in {
		assert(e.type.getCanonical().dstruct is s);
	} body {
		return resolve(e, s.dscope.aliasThis);
	}
	
	Ret[] resolve(Expression e, Class c) in {
		assert(e.type.getCanonical().dclass is c);
	} body {
		return resolve(e, c.dscope.aliasThis);
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

