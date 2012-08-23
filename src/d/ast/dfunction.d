module d.ast.dfunction;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

/**
 * Function Declaration
 */
class FunctionDeclaration : Symbol {
	Type returnType;
	Parameter[] parameters;
	
	this(Location location, string name, Type returnType, Parameter[] parameters) {
		super(location, name);
		
		this.name = name;
		this.returnType = returnType;
		this.parameters = parameters;
	}
}

/**
 * Function Definition
 */
class FunctionDefinition : FunctionDeclaration {
	Statement fbody;
	Scope dscope;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, Statement fbody) {
		super(location, name, returnType, parameters);
		
		this.fbody = fbody;
	}
}

/**
 * Constructor Declaration
 */
class ConstructorDeclaration : Declaration {
	Parameter[] parameters;
	
	this(Location location, Parameter[] parameters) {
		super(location);
		
		this.parameters = parameters;
	}
	
	@property
	final string name() const {
		return "__ctor";
	}
}

/**
 * Constructor Definition
 */
class ConstructorDefinition : ConstructorDeclaration {
	Statement fbody;
	
	this(Location location, Parameter[] parameters, Statement fbody) {
		super(location, parameters);
		
		this.fbody = fbody;
	}
}

/**
 * Destructor Declaration
 */
class DestructorDeclaration : Declaration {
	Parameter[] parameters;
	
	this(Location location, Parameter[] parameters) {
		super(location);
		
		this.parameters = parameters;
	}
	
	@property
	final string name() const {
		return "__dtor";
	}
}

/**
 * Destructor Definition
 */
class DestructorDefinition : DestructorDeclaration {
	Statement fbody;
	
	this(Location location, Parameter[] parameters, Statement fbody) {
		super(location, parameters);
		
		this.fbody = fbody;
	}
}


/**
 * Function types
 */
class FunctionType : SimpleStorageClassType {
	Type returnType;
	Parameter[] parameters;
	bool isVariadic;
	
	this(Location location, Type returnType, Parameter[] parameters, bool isVariadic) {
		super(location);
		
		this.returnType = returnType;
		this.parameters = parameters;
		this.isVariadic = isVariadic;
	}
}

/**
 * Delegate types
 */
class DelegateType : FunctionType {
	this(Location location, Type returnType, Parameter[] parameters, bool isVariadic) {
		super(location, returnType, parameters, isVariadic);
	}
}

/**
 * Function and delegate parameters.
 */
class Parameter : Symbol {
	Type type;
	
	this(Location location, Type type) {
		this(location, type, "");
	}
	
	this(Location location, Type type, string name) {
		super(location, name);
		
		this.type = type;
	}
}

class InitializedParameter : Parameter {
	Expression value;
	
	this(Location location, Type type, string name, Expression value) {
		super(location, type, name);
		
		this.value = value;
	}
}

