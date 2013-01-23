module d.ast.dmodule;

import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;

import std.array;

/**
 * A D module
 */
class Module : Symbol {
	Declaration[] declarations;
	
	Package parent;
	Scope dscope;
	
	this(Location location, string name, string[] packages, Declaration[] declarations) {
		super(location, name);
		
		this.declarations = declarations;
		
		dscope = new Scope(this);
		
		if(packages.length > 0) {
			parent = new Package(location, packages.back, packages[0 .. $-1], dscope);
		} else {
			dscope.addSymbol(this);
		}
	}
}

/**
 * A module delcaration
 */
class Package : Symbol {
	Package parent;
	Scope dscope;
	
	this(Location location, string name, string[] packages, Scope moduleScope) {
		super(location, name);
		
		dscope = new Scope(moduleScope.dmodule);
		
		if(packages.length > 0) {
			parent = new Package(location, packages.back, packages[0 .. $-1], moduleScope);
			parent.dscope.addSymbol(this);
		} else {
			moduleScope.addSymbol(this);
		}
	}
}

