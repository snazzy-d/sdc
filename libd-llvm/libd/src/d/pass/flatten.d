/**
 * This remove everything that isn't meaningfull for compilation from the AST.
 */
module d.pass.flatten;

import d.ast.dmodule;

Module flatten(Module m) {
	auto df = new DeclarationFlatener();
	m.declarations = df.visit(m.declarations);
	
	return m;
}

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

import util.visitor;

class DeclarationFlatener {
	private DeclarationVisitor declarationVisitor;
	
	private Declaration[] workingSet;
	
	this() {
		declarationVisitor  = new DeclarationVisitor(this);
	}
	
final:
	Declaration[] visit(Declaration[] decls) {
		// Ensure we are reentrant.
		auto oldWorkingSet = workingSet;
		scope(exit) workingSet = oldWorkingSet;
		
		workingSet = [];
		
		foreach(decl; decls) {
			visit(decl);
		}
		
		foreach(i, decl; workingSet) {
			workingSet[i] = declarationVisitor.visit(decl);
		}
		
		return workingSet;
	}
	
	void visit(Declaration d) {
		this.dispatch!((Declaration d) {
			workingSet ~= declarationVisitor.visit(d);
		})(d);
	}
	
	void visit(VariablesDeclaration vars) {
		auto decls = vars.variables;
		
		workingSet ~= decls;
	}
}

class DeclarationVisitor {
	private DeclarationFlatener declarationFlatener;
	private StatementVisitor statementVisitor;
	
	this(DeclarationFlatener declarationFlatener) {
		this.declarationFlatener = declarationFlatener;
		
		statementVisitor = new StatementVisitor(this, declarationFlatener);
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDefinition fun) {
		fun.fbody = statementVisitor.visit(fun.fbody);
		
		return fun;
	}
	
	Declaration visit(VariableDeclaration var) {
		return var;
	}
}

import d.ast.statement;

class StatementFlatener {
	private DeclarationFlatener declarationFlatener;
	private StatementVisitor statementVisitor;
	
	private Statement[] workingSet;
	
	this(StatementVisitor statementVisitor, DeclarationFlatener declarationFlatener) {
		this.statementVisitor = statementVisitor;
		this.declarationFlatener = declarationFlatener;
	}
	
final:
	Statement[] visit(Statement[] stmts) {
		// Ensure we are reentrant.
		auto oldWorkingSet = workingSet;
		scope(exit) workingSet = oldWorkingSet;
		
		workingSet = [];
		
		foreach(s; stmts) {
			visit(s);
		}
		
		foreach(i, s; workingSet) {
			workingSet[i] = statementVisitor.visit(s);
		}
		
		return workingSet;
	}
	
	void visit(Statement s) {
		this.dispatch!((Statement s) {
			workingSet ~= statementVisitor.visit(s);
		})(s);
	}
	
	void visit(DeclarationStatement ds) {
		auto decls = declarationFlatener.visit([ds.declaration]);
		
		if(decls.length == 1) {
			ds.declaration = decls[0];
			
			workingSet ~= ds;
		} else {
			Statement[] stmts;
			stmts.length = decls.length;
			
			foreach(i, decl; decls) {
				stmts[i] = new DeclarationStatement(decl);
			}
			
			workingSet ~= stmts;
		}
	}
}

class StatementVisitor {
	private DeclarationVisitor declarationVisitor;
	private DeclarationFlatener declarationFlatener;
	private StatementFlatener statementFlatener;
	
	this(DeclarationVisitor declarationVisitor, DeclarationFlatener declarationFlatener) {
		this.declarationVisitor = declarationVisitor;
		this.declarationFlatener = declarationFlatener;
		
		this.statementFlatener = new StatementFlatener(this, declarationFlatener);
	}
	
final:
	Statement visit(Statement s) {
		return this.dispatch(s);
	}
	
	Statement visit(ExpressionStatement e) {
		return e;
	}
	
	Statement visit(DeclarationStatement d) {
		d.declaration = declarationVisitor.visit(d.declaration);
		
		return d;
	}
	
	Statement visit(BlockStatement b) {
		b.statements = statementFlatener.visit(b.statements);
		
		return b;
	}
	
	Statement visit(IfElseStatement ifs) {
		ifs.then = visit(ifs.then);
		ifs.elseStatement = visit(ifs.elseStatement);
		
		return ifs;
	}
	
	Statement visit(IfStatement ifs) {
		return visit(new IfElseStatement(ifs.location, ifs.condition, ifs.then));
	}
	
	Statement visit(ReturnStatement r) {
		return r;
	}
}

