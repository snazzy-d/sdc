module d.pass.util;

import d.ast.base;
import d.ast.expression;

import sdc.location;

final class Deffered(T) if (is(T == Expression)) : T {
	private T cause;
	private Resolver!T resolver;
	
	this(Location location, T cause, Resolver!T resolver) {
		super(location);
		
		this.cause = cause;
		this.resolver = resolver;
	}
	
	T resolve() {
		if(resolver.test(this)) {
			return resolver.resolve(this);
		}
		
		return this;
	}
}

alias Deffered!Expression DefferedExpression;

private abstract class Resolver(T) if (is(Deffered!T)) {
	bool test(Deffered!T t);
	T resolve(Deffered!T t);
}

auto resolveOrDeffer(alias test, alias resolve, T)(Location location, T t) if(is(Deffered!T) && is(typeof(test(t)) == bool) && is(typeof(resolve(t)) : Identifiable)) {
	if(test(t)) {
		return resolve(t);
	}
	
	alias test testImpl;
	alias resolve resolveImpl;
	
	return new Deffered!T(location, t, new class() Resolver!T {
		override bool test(Deffered!T t) {
			return testImpl(t.cause);
		}
		
		override T resolve(Deffered!T t) {
			auto resolved = resolveImpl(t.cause);
			
			if(auto asT = cast(T) resolved) {
				return asT;
			}
			
			assert(0, typeid(T).toString() ~ " expected");
		}
	});
}

T handleDefferedExpression(alias process, T)(Deffered!T t) /* if(is(typeof(process(t.cause)) : T)) */ {
	// XXX: For unknown reason, this don't seems to work as template constraint.
	static assert(is(typeof(process(t.cause)): T));
	
	t.cause = process(t.cause);
	auto resolved = t.resolve();
	
	if(resolved !is t) {
		return process(resolved);
	}
	
	return new Deffered!T(t.location, t, new class() Resolver!T {
		override bool test(Deffered!T t) {
			T prev;
			do {
				prev = t.cause;
				t.cause = process(t.cause);
			} while(t.cause !is prev);
			
			// if t isn't deffered anymore, we now are done.
			return typeid({ return t.cause; }()) !is typeid(Deffered!T);
		}
		
		override T resolve(Deffered!T t) {
			// This have already been processed when testing.
			return t.cause;
		}
	});
}

