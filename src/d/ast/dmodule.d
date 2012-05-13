module d.ast.dmodule;

import d.ast.base;
import d.ast.declaration;

import sdc.location;

/**
 * A D module
 */
class Module : Node {
	ModuleDeclaration moduleDeclaration;
	Declaration[] declarations;
	
	this(Location lcoation, ModuleDeclaration moduleDeclaration, Declaration[] declarations) {
		super(location);
		
		this.moduleDeclaration = moduleDeclaration;
		this.declarations = declarations;
	}
}

/**
 * A module delcaration
 */
class ModuleDeclaration : Node {
	string name;
	string[] packages;
	
	this(Location location, string name, string[] packages) {
		super(location);
		
		this.name = name;
		this.packages = packages;
	}
}
 
