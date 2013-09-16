module d.ir.dtemplate;

import d.ast.base;

import d.ir.symbol;
import d.ir.type;

/**
 * Templated Type
 * Type that is the result of a template parameter resolution.
 */
class TemplatedType : Type {
	TypeTemplateParameter param;
	
	this(TypeTemplateParameter param) {
		this.param = param;
	}
	
	override string toString(TypeQualifier) const {
		return param.name;
	}
}

