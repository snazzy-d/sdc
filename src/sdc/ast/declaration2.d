module sdc.ast.declaration2;

import sdc.location;
import sdc.ast.expression2;
import sdc.ast.identifier2;
import sdc.ast.statement2;
import sdc.ast.type2;

enum DeclarationType {
	Variable,
	Function,
	Template,
	Alias,
	AliasThis,
	Mixin,
}

interface Declaration {
	@property
	DeclarationType type();
}

/**
 * Any declaration is a statement
 */
class DeclarationStatement : Statement, Declaration {
	private DeclarationType _type;
	
	@property
	DeclarationType type() {
		return _type;
	}
	
	this(Location location, DeclarationType type) {
		super(location);
		
		_type = type;
	}
}

/**
 * Alias of types
 */
class AliasDeclaration : DeclarationStatement {
	Type type;
	string name;
	
	this(Location location, string name, Type type) {
		super(location, DeclarationType.Alias);
		
		this.name = name;
		this.type = type;
	}
}

/**
 * Alias this
 */
class AliasThisDeclaration : DeclarationStatement {
	Identifier identifier;
	
	this(Location location, Identifier identifier) {
		super(location, DeclarationType.AliasThis);
		
		this.identifier = identifier;
	}
}

/**
 * Variable declaration
 */
class VariableDeclaration : DeclarationStatement {
	string name;
	
	this(Location location, string name) {
		super(location, DeclarationType.Variable);
		
		this.name = name;
	}
}

/**
 * Initialized variable declaration
 */
class InitializedVariableDeclaration : VariableDeclaration {
	Expression value;
	
	this(Location location, string name, Expression value) {
		super(location, name);
		
		this.value = value;
	}
}

/**
 * Function Declaration
 */
class FunctionDeclaration : DeclarationStatement {
	string name;
	Type returnType;
	Parameter[] parameters;
	
	this(Location location, string name, Type returnType, Parameter[] parameters) {
		super(location, DeclarationType.Function);
		
		this.name = name;
		this.returnType = returnType;
		this.parameters = parameters;
	}
}

/**
 * Function Declaration
 */
class FunctionDefinition : FunctionDeclaration {
	Statement fbody;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, Statement fbody) {
		super(location, name, returnType, parameters);
		
		this.fbody = fbody;
	}
}

