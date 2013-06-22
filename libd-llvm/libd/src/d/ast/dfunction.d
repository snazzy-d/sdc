module d.ast.dfunction;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

// TODO: remove everything from this file and put it where it belongs.
/+
/**
 * Constructor Declaration
 */
class ConstructorDeclaration : Declaration {
	Parameter[] parameters;
	BlockStatement fbody;
	
	this(Location location, Parameter[] parameters, bool isVariadic, BlockStatement fbody) {
		super(location);
		
		this.parameters = parameters;
		this.fbody = fbody;
	}
}

/**
 * Destructor Declaration
 */
class DestructorDeclaration : Declaration {
	Parameter[] parameters;
	BlockStatement fbody;
	
	this(Location location, Parameter[] parameters, bool isVariadic, BlockStatement fbody) {
		super(location);
		
		this.parameters = parameters;
		this.fbody = fbody;
	}
}
+/

