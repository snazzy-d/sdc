/**
 * This pass handle the main function of a D program.
 */
module d.pass.main;

import d.ast.dmodule;

Module buildMain(Module m) {
	auto md = new MainDetector();
	foreach(i, decl; m.declarations) {
		m.declarations[i] = md.visit(decl);
	}
	
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
	
	Declaration visit(Declaration d) {
		return this.dispatch!(d => d)(d);
	}
	
	Declaration visit(FunctionDeclaration d) {
		if(d.name == "main") {
			throw new Exception("main declaration not supported.");
		}
		
		return d;
	}
	
	private auto handleMain(FunctionDefinition main) {
		// Set the return type to int.
		if(typeid({ return main.returnType; }()) !is typeid(BuiltinType!int)) {
			main.returnType = new BuiltinType!int(main.returnType.location);
			
			// TODO: process function body to replace return; by return 0;
		}
		
		main.name = "_Dmain";
		
		return main;
	}
	
	Declaration visit(FunctionDefinition d) {
		if(d.name == "main") {
			if(returnCheck.visit(d.returnType)) {
				switch(d.parameters.length) {
					case 0 :
						return handleMain(d);
					
					case 1 :
						assert(0, "main vith argument not supported.");
					
					default :
						assert(0, "main must have no more than 1 argument.");
				}
			} else {
				assert(0, "return of main must be void or int.");
			}
		}
		
		return d;
	}
}

class ReturnTypeCheck {
	bool visit(Type t) {
		return this.dispatch!(t => false)(t);
	}
	
	bool visit(BuiltinType!void) {
		return true;
	}
	
	bool visit(BuiltinType!int) {
		return true;
	}
}

