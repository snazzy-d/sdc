/**
 * This pass handle the main function of a D program.
 */
module d.pass.main;

import d.ast.symbol;

import std.algorithm;
import std.array;

auto buildMain(ModuleSymbol m) {
	auto md = new MainDetector();
	
	// TODO: use map reduce ? This failed with 2.060 with template delegate.
	foreach(i, sym; m.symbols) {
		m.symbols[i] = md.visit(sym);
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
	
final:
	Symbol visit(Symbol s) {
		return this.dispatch!(s => s)(s);
	}
	
	private auto handleMain(FunctionSymbol main) {
		main.returnType = new IntegerType(main.returnType.location, IntegerOf!int);
		// TODO: process function body to replace return; by return 0;
		
		main.mangling = "_Dmain";
		
		return main;
	}
	
	Symbol visit(FunctionSymbol s) {
		if(s.name == "main") {
			if(returnCheck.visit(s.returnType)) {
				switch(s.parameters.length) {
					case 0 :
						return handleMain(s);
					
					case 1 :
						assert(0, "main vith argument not supported.");
					
					default :
						assert(0, "main must have no more than 1 argument.");
				}
			} else {
				assert(0, "return of main must be void or int.");
			}
		}
		
		return s;
	}
}

final class ReturnTypeCheck {
	bool visit(Type t) {
		return this.dispatch!(t => false)(t);
	}
	
	bool visit(BuiltinType!void) {
		return true;
	}
	
	bool visit(IntegerType t) {
		return t.type == IntegerOf!int;
	}
}

