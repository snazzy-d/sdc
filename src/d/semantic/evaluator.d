module d.semantic.evaluator;

import d.semantic.base;

import d.ast.expression;

interface Evaluator {
	CompileTimeExpression evaluate(Expression e);
}

