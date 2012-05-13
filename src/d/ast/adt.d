module d.ast.adt;

import d.ast.declaration;
import d.ast.identifier;

import sdc.location;

/**
 * Struct Declaration
 */
class StructDeclaration : Declaration {
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
class ClassDefinition : Declaration {
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
 * Interface Definition
 */
class InterfaceDefinition : Declaration {
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

