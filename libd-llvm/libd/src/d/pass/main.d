/**
 * This pass handle the main function of a D program.
 */
module d.pass.main;

import d.ast.dmodule;

import std.algorithm;
import std.array;

auto buildMain(Module m) {
	auto md = new MainDetector();
	
	m.declarations = m.declarations.map!((Declaration d){ return md.visit(d); }).array();
	
	return m;
}

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

import util.visitor;

class MainDetector {
	private ReturnTypeCheck returnCheck;
	
	this() {
		this.returnCheck = new ReturnTypeCheck();
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch!(d => d)(d);
	}
	
	private auto handleMain(FunctionDefinition main) {
		main.returnType = new IntegerType(main.returnType.location, IntegerOf!int);
		// TODO: process function body to replace return; by return 0;
		
		main.mangling = "_Dmain";
		
		return main;
	}
	
	Declaration visit(FunctionDefinition fun) {
		if(fun.name == "main") {
			if(returnCheck.visit(fun.returnType)) {
				switch(fun.parameters.length) {
					case 0 :
						return handleMain(fun);
					
					case 1 :
						assert(0, "main vith argument not supported.");
					
					default :
						assert(0, "main must have no more than 1 argument.");
				}
			} else {
				assert(0, "return of main must be void or int.");
			}
		}
		
		return fun;
	}
}

final class ReturnTypeCheck {
	bool visit(Type t) {
		return this.dispatch!(t => false)(t);
	}
	
	bool visit(IntegerType t) {
		return t.type == IntegerOf!int;
	}
	
	bool visit(VoidType t) {
		return true;
	}
}

