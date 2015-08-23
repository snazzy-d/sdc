module d.semantic.datalayout;

import d.ir.type;

interface DataLayout {
	uint getSize(Type t);
	uint getAlign(Type t);
}
