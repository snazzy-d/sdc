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
class FunctionDeclaration : ExpressionSymbol {
	Type returnType;
	Parameter[] parameters;
	bool isVariadic;
	
	string funmangle;
	
	Scope dscope;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, bool isVariadic) {
		super(location, name, new FunctionType(location, returnType, parameters, isVariadic));
		
		this.name = name;
		this.returnType = returnType;
		this.parameters = parameters;
		this.isVariadic = isVariadic;
	}
}

/**
 * Function Definition
 */
class FunctionDefinition : FunctionDeclaration {
	BlockStatement fbody;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, bool isVariadic, BlockStatement fbody) {
		super(location, name, returnType, parameters, isVariadic);
		
		this.fbody = fbody;
	}
}

/**
 * Constructor Declaration
 */
class ConstructorDeclaration : Declaration {
	Parameter[] parameters;
	
	this(Location location, Parameter[] parameters, bool isVariadic) {
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
	
	this(Location location, Parameter[] parameters, bool isVariadic, Statement fbody) {
		super(location, parameters, isVariadic);
		
		this.fbody = fbody;
	}
}

/**
 * Destructor Declaration
 */
class DestructorDeclaration : Declaration {
	Parameter[] parameters;
	
	this(Location location, Parameter[] parameters, bool isVariadic) {
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
	
	this(Location location, Parameter[] parameters, bool isVariadic, Statement fbody) {
		super(location, parameters, isVariadic);
		
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
	
	override bool opEquals(const Type t) const {
		if(auto p = cast(FunctionType) t) {
			return this.opEquals(p);
		}
		
		return false;
	}
	
	bool opEquals(const FunctionType t) const {
		if(isVariadic != t.isVariadic) return false;
		if(returnType != t.returnType) return false;
		
		import std.range;
		foreach(p1, p2; lockstep(parameters, t.parameters)) {
			if(p1.type != p2.type) return false;
		}
		
		return true;
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
class Parameter : ExpressionSymbol {
	bool isReference;
	
	this(Location location, Type type) {
		this(location, "", type);
	}
	
	this(Location location, string name, Type type) {
		super(location, name, type);
	}
}

class InitializedParameter : Parameter {
	Expression value;
	
	this(Location location, string name, Type type, Expression value) {
		super(location, name, type);
		
		this.value = value;
	}
}

