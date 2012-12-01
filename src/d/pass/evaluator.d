module d.pass.evaluator;

import d.pass.base;

import d.ast.expression;

interface Evaluator {
	CompileTimeExpression evaluate(Expression e);
}

