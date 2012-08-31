module d.pass.util;

import d.ast.base;
import d.ast.expression;

import sdc.location;

final class DefferedExpression : Expression {
	private Expression cause;
	private Resolver resolver;
	
	this(Location location, Expression cause, Resolver resolver) {
		super(location);
		
		this.cause = cause;
		this.resolver = resolver;
	}
	
	Expression resolve() {
		if(resolver.test(this)) {
			return resolver.resolve(this);
		}
		
		return this;
	}
}

private abstract class Resolver {
	bool test(DefferedExpression e);
	Expression resolve(DefferedExpression e);
}

auto resolveOrDeffer(alias test, alias resolve)(Location location, Expression e) if(is(typeof(test(e)) == bool) && is(typeof(resolve(e)) : Identifiable)) {
	if(test(e)) {
		return resolve(e);
	}
	
	alias test testImpl;
	alias resolve resolveImpl;
	
	return new DefferedExpression(location, e, new class() Resolver {
		override bool test(DefferedExpression e) {
			return testImpl(e.cause);
		}
		
		override Expression resolve(DefferedExpression e) {
			auto resolved = resolveImpl(e.cause);
			
			if(auto re = cast(Expression) resolved) {
				return re;
			}
			
			assert(0, "expression expected");
		}
	});
}

Expression handleDefferedExpression(alias process)(DefferedExpression e) if(is(typeof(process(cast(Expression) e)) : Expression)) {
	e.cause = process(e.cause);
	auto resolved = e.resolve();
	
	if(resolved !is e) {
		return process(resolved);
	}
	
	return new DefferedExpression(e.location, e, new class() Resolver {
		override bool test(DefferedExpression e) {
			e.cause = process(e.cause);
			
			if(auto def = cast(DefferedExpression) e.cause) {
				return def.resolver.test(def);
			}
			
			// e isn't deffered anymore, we now are done.
			return true;
		}
		
		override Expression resolve(DefferedExpression e) {
			// This have already been processed when testing.
			return e.cause;
		}
	});
}

