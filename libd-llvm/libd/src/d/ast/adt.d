module d.ast.adt;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

/**
 * Class Declaration
 */
class ClassDeclaration : TypeSymbol {
	Type[] bases;
	Declaration[] members;
	
	SymbolScope dscope;
	
	this(Location location, string name, Type[] bases, Declaration[] members) {
		super(location, name);
		
		this.name = name;
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Interface Declaration
 */
class InterfaceDeclaration : TypeSymbol {
	Type[] bases;
	Declaration[] members;
	
	SymbolScope dscope;
	
	this(Location location, string name, Type[] bases, Declaration[] members) {
		super(location, name);
		
		this.bases = bases;
		this.members = members;
	}
}

/**
 * Struct Definition
 */
class StructDeclaration : TypeSymbol {
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
class UnionDeclaration : TypeSymbol {
	Declaration[] members;
	
	this(Location location, string name, Declaration[] members) {
		super(location, name);
		
		this.members = members;
	}
}

/**
 * Enum Declaration
 */
class EnumDeclaration : TypeSymbol {
	Type type;
	VariableDeclaration[] enumEntries;
	
	SymbolScope dscope;
	
	this(Location location, string name, Type type, VariableDeclaration[] enumEntries) {
		super(location, name);
		
		this.type = type;
		this.enumEntries = enumEntries;
	}
}

