module d.semantic.evaluator;

import d.ir.constant;
import d.ir.expression;

interface Evaluator {
	Constant evaluate(Expression e);

	ulong evalIntegral(Expression e);
	string evalString(Expression e);
}
