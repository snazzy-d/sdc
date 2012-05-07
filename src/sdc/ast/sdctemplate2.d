module sdc.ast.sdctemplate2;

import sdc.location;
import sdc.ast.declaration2;

/**
 * Template declaration
 */
class TemplateDeclaration : Declaration {
	string name;
	TemplateParameter[] parameters;
	Declaration[] declarations;
	
	this(Location location, string name, TemplateParameter[] parameters, Declaration[] declarations) {
		super(location, DeclarationType.Template);
		
		this.name = name;
		this.parameters = parameters;
		this.declarations = declarations;
	}
}

enum TemplateParameterType {
	Type,
	Value,
	Alias,
	Tuple,
	This
}

class TemplateParameter : Declaration {
	this(Location location, DeclarationType type) {
		super(location, type);
	}
}

