/**
 * This remove everything that isn't meaningfull for compilation from the AST.
 */
module d.pass.flatten;

import d.pass.base;

import d.ast.dmodule;

import std.algorithm;
import std.array;

auto flatten(Module m) {
	auto pass = new FlattenPass();
	
	return pass.visit(m);
}

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class FlattenPass {
	private DeclarationVisitor declarationVisitor;
	private DeclarationFlatener declarationFlatener;
	private StatementVisitor statementVisitor;
	private StatementFlatener statementFlatener;
	private ExpressionVisitor expressionVisitor;
	private TypeVisitor typeVisitor;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		declarationFlatener	= new DeclarationFlatener(this);
		statementVisitor	= new StatementVisitor(this);
		statementFlatener	= new StatementFlatener(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
	}
	
final:
	Module visit(Module m) {
		m.declarations = visit(m.declarations);
		
		return m;
	}
	
	auto visit(Declaration decl) {
		return declarationVisitor.visit(decl);
	}
	
	auto visit(Declaration[] decls) {
		return declarationFlatener.visit(decls);
	}
	
	auto visit(Statement stmt) {
		return statementVisitor.visit(stmt);
	}
	
	auto visit(Statement[] stmts) {
		return statementFlatener.visit(stmts);
	}
	
	auto visit(Expression e) {
		return expressionVisitor.visit(e);
	}
	
	auto visit(Type t) {
		return typeVisitor.visit(t);
	}
}

import d.ast.dfunction;
import d.ast.dtemplate;

class DeclarationVisitor {
	private FlattenPass pass;
	
	bool isStatic = true;
	
	this(FlattenPass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDefinition fun) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = false;
		
		fun.fbody = pass.visit(fun.fbody);
		
		return fun;
	}
	
	Declaration visit(VariableDeclaration var) {
		var.isStatic = isStatic;
		
		var.type = pass.visit(var.type);
		
		return var;
	}
	
	Declaration visit(TemplateDeclaration tpl) {
		tpl.declarations = pass.visit(tpl.declarations);
		
		return tpl;
	}
}

class DeclarationFlatener {
	private FlattenPass pass;
	
	private Declaration[] workingSet;
	
	this(FlattenPass pass) {
		this.pass = pass;
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
		
		return workingSet.map!(d => pass.visit(d)).array();
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

class StatementVisitor {
	private FlattenPass pass;
	
	this(FlattenPass pass) {
		this.pass = pass;
	}
	
final:
	Statement visit(Statement s) {
		return this.dispatch(s);
	}
	
	Statement visit(ExpressionStatement e) {
		e.expression = pass.visit(e.expression);
		
		return e;
	}
	
	// XXX: Statement is supposed to be flattened before.
	// FIXME: it isn't always the case. This precondition have to be handled somehow.
	Statement visit(DeclarationStatement ds) {
		auto decls = pass.visit([ds.declaration]);
		
		assert(decls.length == 1, "flat flat");
		
		ds.declaration = decls[0];
		
		return ds;
	}
	
	Statement visit(BlockStatement b) {
		b.statements = pass.visit(b.statements);
		
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
		w.condition = pass.visit(w.condition);
		
		return w;
	}
	
	Statement visit(DoWhileStatement w) {
		w.statement = visit(w.statement);
		w.condition = pass.visit(w.condition);
		
		return w;
	}
	
	Statement visit(ForStatement f) {
		f.initialize = visit(f.initialize);
		f.statement = visit(f.statement);
		
		f.condition = pass.visit(f.condition);
		f.increment = pass.visit(f.increment);
		
		return f;
	}
	
	Statement visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
		
		return r;
	}
}

// TODO: remove this and use BlockStatement to replace it. Use ScopeBlockStatement for explicit blocks statements.
class StatementFlatener {
	private FlattenPass pass;
	
	private Statement[] workingSet;
	
	this(FlattenPass pass) {
		this.pass = pass;
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
		
		return workingSet.map!(s => pass.visit(s))().array();
	}
	
	void visit(Statement s) {
		this.dispatch!((Statement s) {
			workingSet ~= s;
		})(s);
	}
	
	void visit(DeclarationStatement ds) {
		auto decls = pass.visit([ds.declaration]);
		
		if(decls.length == 1) {
			ds.declaration = decls[0];
			workingSet ~= ds;
		} else {
			workingSet ~= decls.map!(d => new DeclarationStatement(d)).array();
		}
	}
}

class ExpressionVisitor {
	private FlattenPass pass;
	
	this(FlattenPass pass) {
		this.pass = pass;
	}
	
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

class TypeVisitor {
	private FlattenPass pass;
	
	this(FlattenPass pass) {
		this.pass = pass;
	}
	
final:
	Type visit(Type t) {
		return this.dispatch!(t => t)(t);
	}
	
	Type visit(TypeofType t) {
		t.expression = pass.visit(t.expression);
		
		return t;
	}
}

