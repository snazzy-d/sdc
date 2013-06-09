module d.ast.dfunction;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

// TODO: remove everything from this file and put it where it belongs.

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
	
	@property
	final string name() const {
		return "__ctor";
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
	
	@property
	final string name() const {
		return "__dtor";
	}
}

/**
 * Function types
 */
class FunctionType : Type {
	Type returnType;
	Parameter[] parameters;
	bool isVariadic;
	
	string linkage;
	
	this(string linkage, Type returnType, Parameter[] parameters, bool isVariadic) {
		this.returnType = returnType;
		this.parameters = parameters;
		this.isVariadic = isVariadic;
		
		this.linkage = linkage;
	}
	
	override bool opEquals(const Type t) const {
		if(auto p = cast(FunctionType) t) {
			return this.opEquals(p);
		}
		
		return false;
	}
	
	bool opEquals(const FunctionType t) const {
		if(isVariadic != t.isVariadic) return false;
		if(linkage != t.linkage) return false;
		
		if(returnType != t.returnType) return false;
		if(parameters.length != t.parameters.length) return false;
		
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
	Parameter context;
	
	this(string linkage, Type returnType, Parameter context, Parameter[] parameters, bool isVariadic) {
		super(linkage, returnType, parameters, isVariadic);
		
		this.context = context;
	}
	
	override bool opEquals(const Type t) const {
		if(auto p = cast(DelegateType) t) {
			return this.opEquals(p);
		}
		
		return false;
	}
	
	bool opEquals(const DelegateType t) const {
		if(context != t.context) return false;
		
		alias ftOpEquals = FunctionType.opEquals;
		return ftOpEquals(t);
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
	
	invariant() {
		assert(type !is null, "A parameter must have a type.");
	}
}

class InitializedParameter : Parameter {
	Expression value;
	
	this(Location location, string name, Type type, Expression value) {
		super(location, name, type);
		
		this.value = value;
	}
}

