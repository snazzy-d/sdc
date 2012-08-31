module d.pass.util;

import d.ast.base;
import d.ast.expression;

import sdc.location;

final class DefferedExpression : Expression {
	Expression expression;
	
	private Resolver resolver;
	
	this(Location location, Expression expression, Resolver resolver) {
		super(location);
		
		this.expression = expression;
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
			return testImpl(e.expression);
		}
		
		override Expression resolve(DefferedExpression e) {
			auto resolved = resolveImpl(e.expression);
			
			if(auto re = cast(Expression) resolved) {
				return re;
			}
			
			assert(0, "expression expected");
		}
	});
}

auto handleDefferedExpression(alias process)(DefferedExpression e) if(is(typeof(process(e.expression)) : Expression)) {
	e.expression = process(e.expression);
	
	auto resolved = e.resolve();
	
	if(resolved !is e) {
		return process(resolved);
	}
	
	return new DefferedExpression(e.location, e, new class() Resolver {
		override bool test(DefferedExpression e) {
			auto cause = e.expression;
			e.expression = process(cause);
			
			return (e.expression !is cause);
		}
		
		override Expression resolve(DefferedExpression e) {
			return e.expression;
		}
	});
}

