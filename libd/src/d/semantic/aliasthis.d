module d.semantic.aliasthis;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;

import d.context.location;

import d.exception;

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
		return resolve(e, a.aliasThis);
	}
	
	import d.context.name;
	private Ret[] resolve(Expression e, Name[] aliases) {
		import d.semantic.identifier;
		import std.algorithm, std.array;
		return aliases
			.map!(n => SymbolResolver!identifiableHandler(pass).resolveInExpression(e.location, e, n))
			.filter!(i => !i.isError())
			.map!(c => c.apply!handler())
			.array();
	}
}
