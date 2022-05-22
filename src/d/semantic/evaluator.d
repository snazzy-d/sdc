module d.semantic.evaluator;

import d.ir.expression;

interface Evaluator {
	CompileTimeExpression evaluate(Expression e);

	ulong evalIntegral(Expression e);
	string evalString(Expression e);
}
