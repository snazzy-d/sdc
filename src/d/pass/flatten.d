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
	Declaration[] visit(Declaration[] decls) {
		
		return decls;
	}
}

class DeclarationDefVisitor {
	private DeclarationVisitor declarationVisitor;
	
	this() {
		declarationVisitor  = new DeclarationVisitor();
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDefinition fun) {
		return declarationVisitor.visit(fun);
	}
}

class DeclarationVisitor {
	private StatementVisitor statementVisitor;
	
	this() {
		statementVisitor = new StatementVisitor(this);
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDefinition fun) {
		fun.fbody = statementVisitor.visit(fun.fbody);
		
		return fun;
	}
	
	// TODO: expand variables into several declarations.
	Declaration visit(VariablesDeclaration decls) {
		return decls;
	}
}

import d.ast.statement;

class StatementVisitor {
	private DeclarationVisitor declarationVisitor;
	
	this(DeclarationVisitor declarationVisitor) {
		this.declarationVisitor = declarationVisitor;
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
		foreach(i, s; b.statements) {
			b.statements[i] = visit(s);
		}
		
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

