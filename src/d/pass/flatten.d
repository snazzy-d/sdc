/**
 * This remove everything that isn't meaningfull for compilation from the AST.
 * Additionnaly, declaration are replaced by symbols and scope are prepared.
 */
module d.pass.flatten;

import d.ast.dmodule;
import d.ast.symbol;

import std.algorithm;
import std.array;

auto flatten(Module m) {
	auto msym = new ModuleSymbol(m.moduleDeclaration);
	auto dv = new DeclarationVisitor(msym);
	
	msym.symbols = dv.declarationFlatener.visit(m.declarations);
	
	return msym;
}

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

import util.visitor;

class DeclarationVisitor {
	private DeclarationFlatener declarationFlatener;
	private StatementVisitor statementVisitor;
	
	private ScopeSymbol parent;
	
	this(ScopeSymbol parent) {
		declarationFlatener = new DeclarationFlatener(this);
		statementVisitor = new StatementVisitor(this, declarationFlatener);
		
		this.parent = parent;
	}
	
final:
	Symbol visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Symbol visit(FunctionDefinition fun) {
		auto funsym = new FunctionSymbol(fun, parent);
		
		auto oldParent = parent;
		scope(exit) parent = oldParent;
		
		parent = funsym;
		
		fun.fbody = statementVisitor.visit(fun.fbody);
		
		return funsym;
	}
	
	Symbol visit(VariableDeclaration var) {
		return new VariableSymbol(var, parent);
	}
}

class DeclarationFlatener {
	private DeclarationVisitor declarationVisitor;
	
	private Declaration[] workingSet;
	
	this(DeclarationVisitor declarationVisitor) {
		this.declarationVisitor = declarationVisitor;
	}
	
final:
	Symbol[] visit(Declaration[] decls) {
		// Ensure we are reentrant.
		auto oldWorkingSet = workingSet;
		scope(exit) workingSet = oldWorkingSet;
		
		workingSet = [];
		
		foreach(decl; decls) {
			visit(decl);
		}
		
		return workingSet.map!(d => declarationVisitor.visit(d))().array();
	}
	
	void visit(Declaration d) {
		this.dispatch!((Declaration d) {
			workingSet ~= d;
		})(d);
	}
	
	void visit(VariablesDeclaration vars) {
		auto decls = vars.variables;
		
		workingSet ~= decls;
	}
}

import d.ast.statement;

class StatementVisitor {
	private DeclarationVisitor declarationVisitor;
	private DeclarationFlatener declarationFlatener;
	private StatementFlatener statementFlatener;
	private ExpressionVisitor expressionVisitor;
	
	this(DeclarationVisitor declarationVisitor, DeclarationFlatener declarationFlatener) {
		this.declarationVisitor = declarationVisitor;
		this.declarationFlatener = declarationFlatener;
		
		statementFlatener = new StatementFlatener(this, declarationFlatener);
		expressionVisitor = new ExpressionVisitor();
	}
	
final:
	Statement visit(Statement s) {
		return this.dispatch(s);
	}
	
	Statement visit(ExpressionStatement e) {
		e.expression = expressionVisitor.visit(e.expression);
		
		return e;
	}
	
	// Note: SymbolStatement have to be flatened before. This function assume it is done.
	Statement visit(SymbolStatement s) {
		return s;
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
		r.value = expressionVisitor.visit(r.value);
		
		return r;
	}
}

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
		
		return workingSet.map!(s => statementVisitor.visit(s))().array();
	}
	
	void visit(Statement s) {
		this.dispatch!((Statement s) {
			workingSet ~= statementVisitor.visit(s);
		})(s);
	}
	
	void visit(DeclarationStatement ds) {
		auto syms = declarationFlatener.visit([ds.declaration]);
		
		if(syms.length == 1) {
			workingSet ~= new SymbolStatement(syms[0]);
		} else {
			Statement[] stmts;
			stmts.length = syms.length;
			
			foreach(i, sym; syms) {
				stmts[i] = new SymbolStatement(sym);
			}
			
			workingSet ~= stmts;
		}
	}
}

import d.ast.expression;

class ExpressionVisitor {
final:
	Expression visit(Expression e) {
		return this.dispatch!(e => e)(e);
	}
	
	Expression visit(ParenExpression e) {
		return e.expression;
	}
}

