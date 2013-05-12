module d.semantic.backend;

import d.ast.dmodule;

interface Backend {
	void visit(Module mod);
}

