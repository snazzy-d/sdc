module d.semantic.aliasthis;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

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
		auto t = peelAlias(e.type).type;
		
		if (auto st = cast(StructType) t) {
			return resolve(e, st);
		} else if (auto ct = cast(ClassType) t) {
			return resolve(e, ct);
		}
		
		return [];
	}
	
	Ret[] resolve(Expression e, StructType t) in {
		assert(t is peelAlias(e.type).type);
	} body {
		return resolve(e, t.dstruct.dscope.aliasThis);
	}
	
	Ret[] resolve(Expression e, ClassType t) in {
		assert(t is peelAlias(e.type).type);
	} body {
		return resolve(e, t.dclass.dscope.aliasThis);
	}
	
	Ret[] resolve(Expression e, Name[] aliases) {
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

