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
	auto cause = e.cause;
	e.cause = process(cause);
	
	if(cause !is e.cause) {
		return process(e.resolve());
	}
	
	return new DefferedExpression(e.location, e, new class() Resolver {
		override bool test(DefferedExpression e) {
			auto cause = e.cause;
			e.cause = process(cause);
			
			return (cause !is e.cause);
		}
		
		override Expression resolve(DefferedExpression e) {
			return e.cause;
		}
	});
}

