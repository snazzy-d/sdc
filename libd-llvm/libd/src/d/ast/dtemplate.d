module d.ast.dtemplate;

import d.ast.base;
import d.ast.declaration;
import d.ast.type;

/**
 * Template declaration
 */
class TemplateDeclaration : Declaration {
	string name;
	TemplateParameter[] parameters;
	Declaration[] declarations;
	
	this(Location location, string name, TemplateParameter[] parameters, Declaration[] declarations) {
		super(location);
		
		this.name = name;
		this.parameters = parameters;
		this.declarations = declarations;
	}
}

/**
 * Super class for all templates parameters
 */
class TemplateParameter : Declaration {
	this(Location location) {
		super(location);
	}
}

/**
 * Types templates parameters
 */
class TypeTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * This templates parameters
 */
class ThisTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Tuple templates parameters
 */
class TupleTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Value template parameters
 */
class ValueTemplateParameter : TemplateParameter {
	string name;
	Type type;
	
	this(Location location, string name, Type type) {
		super(location);
		
		this.name = name;
		this.type = type;
	}
}

/**
 * Alias template parameter
 */
class AliasTemplateParameter : TemplateParameter {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Typed alias template parameter
 */
class TypedAliasTemplateParameter : AliasTemplateParameter {
	Type type;
	
	this(Location location, string name, Type type) {
		super(location, name);
		
		this.type = type;
	}
}

