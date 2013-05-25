module d.semantic.evaluator;

import d.ast.expression;

interface Evaluator {
	CompileTimeExpression evaluate(Expression e);
}

