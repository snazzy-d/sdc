module d.semantic.backend;

import d.ir.symbol;

interface Backend {
	void visit(Module mod);
}

