/**
 * This remove everything that isn't meaningfull for compilation from the AST.
 */
module d.pass.flatten;

import d.pass.base;

import d.ast.dmodule;

import std.algorithm;
import std.array;

auto flatten(Module m) {
	auto dv = new DeclarationVisitor();
	
	m.declarations = dv.declarationFlatener.visit(m.declarations);
	
	return m;
}

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.type;

class DeclarationVisitor {
	private DeclarationFlatener declarationFlatener;
	private StatementVisitor statementVisitor;
	
	bool isStatic = true;
	
	this() {
		declarationFlatener = new DeclarationFlatener(this);
		statementVisitor = new StatementVisitor(this, declarationFlatener);
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDefinition fun) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = false;
		
		fun.fbody = statementVisitor.visit(fun.fbody);
		
		return fun;
	}
	
	Declaration visit(VariableDeclaration var) {
		var.isStatic = isStatic;
		
		return var;
	}
}

class DeclarationFlatener {
	private DeclarationVisitor declarationVisitor;
	
	private Declaration[] workingSet;
	
	this(DeclarationVisitor declarationVisitor) {
		this.declarationVisitor = declarationVisitor;
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
		
		return workingSet.map!(d => declarationVisitor.visit(d)).array();
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
	
	// XXX: Statement is supposed to be flattened before.
	// FIXME: it isn't always the case. This precondition have to be handled somehow.
	Statement visit(DeclarationStatement ds) {
		auto decls = declarationFlatener.visit([ds.declaration]);
		
		assert(decls.length == 1, "flat flat");
		
		ds.declaration = decls[0];
		
		return ds;
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
	
	Statement visit(WhileStatement w) {
		w.statement = visit(w.statement);
		w.condition = expressionVisitor.visit(w.condition);
		
		return w;
	}
	
	Statement visit(DoWhileStatement w) {
		w.statement = visit(w.statement);
		w.condition = expressionVisitor.visit(w.condition);
		
		return w;
	}
	
	Statement visit(ForStatement f) {
		f.initialize = visit(f.initialize);
		f.statement = visit(f.statement);
		f.condition = expressionVisitor.visit(f.condition);
		f.increment = expressionVisitor.visit(f.increment);
		
		return f;
	}
	
	Statement visit(ReturnStatement r) {
		r.value = expressionVisitor.visit(r.value);
		
		return r;
	}
}

// TODO: remove this and use BlockStatement to replace it. Use ScopeBlockStatement for explicit blocks statements.
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
			workingSet ~= s;
		})(s);
	}
	
	void visit(DeclarationStatement ds) {
		auto decls = declarationFlatener.visit([ds.declaration]);
		
		workingSet ~= decls.map!(d => new DeclarationStatement(d)).array();
	}
}

import d.ast.expression;

class ExpressionVisitor {
final:
	Expression visit(Expression e) {
		return this.dispatch(e);
	}
	
	Expression visit(BooleanLiteral bl) {
		return bl;
	}
	
	Expression visit(IntegerLiteral!true il) {
		return il;
	}
	
	Expression visit(IntegerLiteral!false il) {
		return il;
	}
	
	Expression visit(FloatLiteral fl) {
		return fl;
	}
	
	Expression visit(CharacterLiteral cl) {
		return cl;
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		return e;
	}
	
	Expression visit(AssignExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(AddExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(SubExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(MulExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(DivExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(ModExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(EqualityExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(NotEqualityExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(GreaterExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(GreaterEqualExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LessExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LessEqualExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LogicalAndExpression e) {
		return handleBinaryExpression(e);
	}
	
	Expression visit(LogicalOrExpression e) {
		return handleBinaryExpression(e);
	}
	
	private auto handleUnaryExpression(UnaryExpression)(UnaryExpression e) {
		e.expression = visit(e.expression);
		
		return e;
	}
	
	Expression visit(PreIncrementExpression e) {
		return handleUnaryExpression(e);
	}
	
	Expression visit(PreDecrementExpression e) {
		return handleUnaryExpression(e);
	}
	
	Expression visit(PostIncrementExpression e) {
		return handleUnaryExpression(e);
	}
	
	Expression visit(PostDecrementExpression e) {
		return handleUnaryExpression(e);
	}
	
	Expression visit(CastExpression e) {
		e.expression = visit(e.expression);
		
		return e;
	}
	
	Expression visit(CallExpression c) {
		c.arguments = c.arguments.map!(arg => visit(arg)).array();
		
		c.callee = visit(c.callee);
		
		return c;
	}
	
	Expression visit(IdentifierExpression e) {
		return e;
	}
	
	Expression visit(ParenExpression e) {
		return e.expression;
	}
}

