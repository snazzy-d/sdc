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
	Struct,
	Class,
	Enum,
	Alias,
	AliasThis,
	Import,
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
 * Variables declaration
 */
class VariablesDeclaration : DeclarationStatement {
	Type type;
	Expression[string] variables;
	
	this(Location location, Expression[string] variables, Type type) {
		super(location, DeclarationType.Variable);
		
		this.type = type;
		this.variables = variables;
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
 * Function Definition
 */
class FunctionDefinition : FunctionDeclaration {
	Statement fbody;
	
	this(Location location, string name, Type returnType, Parameter[] parameters, Statement fbody) {
		super(location, name, returnType, parameters);
		
		this.fbody = fbody;
	}
}

/**
 * Struct Declaration
 */
class StructDeclaration : DeclarationStatement {
	string name;
	
	this(Location location, string name) {
		super(location, DeclarationType.Struct);
		
		this.name = name;
	}
}

/**
 * Struct Definition
 */
class StructDefinition : StructDeclaration {
	Declaration[] members;
	
	this(Location location, string name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Class Definition
 */
class ClassDefinition : DeclarationStatement {
	string name;
	Identifier[] bases;
	Declaration[] members;
	
	this(Location location, string name, Identifier[] bases, Declaration[] members) {
		super(location, DeclarationType.Class);
		
		this.name = name;
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Import declaration
 */
class ImportDeclaration : DeclarationStatement {
	string name;
	Identifier[] modules;
	
	this(Location location, Identifier[] modules) {
		super(location, DeclarationType.Import);
		
		this.modules = modules;
	}
}

