module d.semantic.evaluator;

import d.ir.constant;
import d.ir.value;

interface Evaluator {
	Constant evaluate(Value value);

	ulong evalIntegral(Value value);
	string evalString(Value value);
}
