module d.semantic.aliasthis;

import d.semantic.semantic;

import d.ir.symbol;
import d.ir.value;

import source.location;

import source.exception;

struct AliasThisResolver(alias handler) {
	private SemanticPass pass;
	alias pass this;

	alias Ret = typeof(handler(Symbol.init));

	this(SemanticPass pass) {
		this.pass = pass;
	}

	Ret[] resolve(Location location, Value v) {
		auto t = v.type.getCanonical();

		import d.ir.type;
		if (!t.isAggregate) {
			return [];
		}

		return resolve(location, v, t.aggregate);
	}

	Ret[] resolve(Location location, Value v, Aggregate a)
			in(v.type.getCanonical().aggregate is a) {
		return resolve(location, v, a.aliasThis);
	}

	import source.name;
	private Ret[] resolve(Location location, Value v, Name[] aliases) {
		// FIXME: Identifiers should be resolved in values.
		auto e = v.getExpression(location);

		import d.semantic.identifier;
		import std.algorithm, std.array;
		return aliases
			.map!(n => IdentifierResolver(pass).buildIn(location, e, n))
			.filter!(i => !i.isError()).map!(c => c.apply!handler()).array();
	}
}
