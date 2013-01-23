module d.ast.adt;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

/**
 * Class Definition
 */
class ClassDefinition : TypeSymbol {
	Identifier[] bases;
	Declaration[] members;
	
	SymbolScope dscope;
	
	this(Location location, string name, Identifier[] bases, Declaration[] members) {
		super(location, name);
		
		this.name = name;
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Interface Definition
 */
class InterfaceDefinition : TypeSymbol {
	Identifier[] bases;
	Declaration[] members;
	
	SymbolScope dscope;
	
	this(Location location, string name, Identifier[] bases, Declaration[] members) {
		super(location, name);
		
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Struct Declaration
 */
class StructDeclaration : TypeSymbol {
	this(Location location, string name) {
		super(location, name);
	}
}

/**
 * Struct Definition
 */
class StructDefinition : StructDeclaration {
	Declaration[] members;
	
	SymbolScope dscope;
	
	this(Location location, string name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Union Declaration
 */
class UnionDeclaration : Declaration {
	string name;
	
	this(Location location, string name) {
		super(location);
		
		this.name = name;
	}
}

/**
 * Union Definition
 */
class UnionDefinition : UnionDeclaration {
	Declaration[] members;
	
	this(Location location, string name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Enum
 */
class EnumDeclaration : TypeSymbol {
	Type type;
	VariableDeclaration[] enumEntries;
	
	SymbolScope dscope;
	
	this(Location location, string name, Type type, VariableDeclaration[] enumEntries) {
		super(location, name);
		
		this.type = new EnumType(type, this);
		this.enumEntries = enumEntries;
	}
}

/**
 * Enum type
 */
class EnumType : SuffixType {
	EnumDeclaration declaration;
	
	this(Type type, EnumDeclaration declaration) {
		super(type.location, type);
		
		this.declaration = declaration;
	}
	
	override bool opEquals(const Type t) const {
		return this is t;
	}
}

