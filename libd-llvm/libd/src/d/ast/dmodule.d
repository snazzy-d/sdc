module d.ast.dmodule;

import d.ast.base;
import d.ast.declaration;

// TODO: merge into declaration
/**
 * A package delcaration
 */
class Package : NamedDeclaration {
	Package parent;
	
	this(Location location, Name name, Name[] packages) {
		super(location, name);
		
		if(packages.length > 0) {
			parent = new Package(location, packages[$ - 1], packages[0 .. $-1]);
		}
	}
}

/**
 * A D module
 */
class Module : Package {
	Declaration[] declarations;
	
	this(Location location, Name name, Name[] packages, Declaration[] declarations) {
		super(location, name, packages);
		
		this.declarations = declarations;
	}
}

