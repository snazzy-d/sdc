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
import d.ast.expression;
import d.ast.statement;
import d.ast.type;

import util.visitor;

class MainDetector {
	private FunctionDefinition main;
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch!(d => d)(d);
	}
	
	private auto handleMain(FunctionDefinition main) {
		this.main = main;
		
		visit(main.returnType);
		
		main.funmangle = "_Dmain";
		
		return main;
	}
	
	Declaration visit(FunctionDefinition fun) {
		if(fun.name == "main") {
			switch(fun.parameters.length) {
				case 0 :
					return handleMain(fun);
				
				case 1 :
					assert(0, "main vith argument not supported.");
				
				default :
					assert(0, "main must have no more than 1 argument.");
			}
		}
		
		return fun;
	}
	
	void visit(Type t) {
		return this.dispatch!(function bool(Type t) {
			assert(0, "return of main must be void or int.");
		})(t);
	}
	
	void visit(IntegerType t) {
		assert(t.type == IntegerOf!int, "return type must be void or int.");
	}
	
	void visit(VoidType t) {
		auto retVal = makeLiteral(t.location, 0);
		auto ret = new ReturnStatement(t.location, retVal);
		
		main.returnType = retVal.type;
		
		main.fbody = (new StatementVisitor()).visit(main.fbody);
		main.fbody.statements ~= ret;
	}
}

class StatementVisitor {
	
final:
	Statement visit(Statement stmt) {
		return this.dispatch(stmt);
	}
	
	Statement visit(ExpressionStatement e) {
		return e;
	}
	
	Statement visit(DeclarationStatement d) {
		return d;
	}
	
	BlockStatement visit(BlockStatement b) {
		b.statements = b.statements.map!(s => visit(s)).array();
		
		return b;
	}
	
	Statement visit(IfElseStatement ifs) {
		ifs.then = visit(ifs.then);
		ifs.elseStatement = visit(ifs.elseStatement);
		
		return ifs;
	}
	
	Statement visit(WhileStatement w) {
		w.statement = visit(w.statement);
		
		return w;
	}
	
	Statement visit(DoWhileStatement w) {
		w.statement = visit(w.statement);
		
		return w;
	}
	
	Statement visit(ForStatement f) {
		f.initialize = visit(f.initialize);
		f.statement = visit(f.statement);
		
		return f;
	}
}

