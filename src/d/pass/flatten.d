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
	
	string linkage = "D";
	bool isStatic = true;
	
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

import d.ast.adt;
import d.ast.dfunction;
import d.ast.dscope;
import d.ast.dtemplate;

class DeclarationVisitor {
	private FlattenPass pass;
	alias pass this;
	
	this(FlattenPass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Declaration visit(FunctionDeclaration d) {
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		return d;
	}
	
	Declaration visit(FunctionDefinition d) {
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		auto oldLinkage = linkage;
		scope(exit) linkage = oldLinkage;
		
		linkage = "D";
		
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = false;
		
		d.fbody = statementVisitor.visit(d.fbody);
		
		return d;
	}
	
	Declaration visit(VariableDeclaration d) {
		d.linkage = linkage;
		d.isStatic = isStatic;
		
		d.type = pass.visit(d.type);
		
		return d;
	}
	
	Declaration visit(StructDefinition d) {
		d.linkage = linkage;
		
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = false;
		
		d.members = pass.visit(d.members);
		
		return d;
	}
	
	Declaration visit(TemplateDeclaration tpl) {
		tpl.declarations = pass.visit(tpl.declarations);
		
		return tpl;
	}
	
	Declaration visit(AliasDeclaration a) {
		a.type = pass.visit(a.type);
		
		return a;
	}
}

class DeclarationFlatener {
	private FlattenPass pass;
	alias pass this;
	
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
		
		return workingSet;
	}
	
	void visit(Declaration d) {
		this.dispatch!((Declaration d) {
			workingSet ~= pass.visit(d);
		})(d);
	}
	
	void visit(VariablesDeclaration d) {
		// XXX: hacking around some cast limitation.
		workingSet ~= visit(d.variables.map!(function Declaration(Declaration d) { return d; }).array());
	}
	
	void visit(LinkageDeclaration d) {
		auto oldLinkage = linkage;
		scope(exit) linkage = oldLinkage;
		
		linkage = d.linkage;
		
		workingSet ~= visit(d.declarations);
	}
	
	void visit(StaticDeclaration d) {
		auto oldIsStatic = isStatic;
		scope(exit) isStatic = oldIsStatic;
		
		isStatic = true;
		
		workingSet ~= visit(d.declarations);
	}
}

class StatementVisitor {
	private FlattenPass pass;
	alias pass this;
	
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
	
	BlockStatement visit(BlockStatement b) {
		b.statements = pass.visit(b.statements);
		
		return b;
	}
	
	Statement visit(IfElseStatement ifs) {
		ifs.then = visit(ifs.then);
		ifs.elseStatement = visit(ifs.elseStatement);
		
		ifs.condition = pass.visit(ifs.condition);
		
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
	alias pass this;
	
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
	alias pass this;
	
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
	
	Expression visit(StringLiteral e) {
		return e;
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
	
	Expression visit(AddressOfExpression e) {
		return handleUnaryExpression(e);
	}
	
	Expression visit(DereferenceExpression e) {
		return handleUnaryExpression(e);
	}
	
	Expression visit(CastExpression e) {
		e.expression = visit(e.expression);
		e.type = pass.visit(e.type);
		
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
	
	Expression visit(IndexExpression e) {
		e.indexed = visit(e.indexed);
		
		e.parameters = e.parameters.map!(e => visit(e)).array();
		
		return e;
	}
}

class TypeVisitor {
	private FlattenPass pass;
	
	this(FlattenPass pass) {
		this.pass = pass;
	}
	
final:
	Type visit(Type t) {
		return this.dispatch(t);
	}
	
	Type visit(BooleanType t) {
		return t;
	}
	
	Type visit(IntegerType t) {
		return t;
	}
	
	Type visit(FloatType t) {
		return t;
	}
	
	Type visit(CharacterType t) {
		return t;
	}
	
	Type visit(VoidType t) {
		return t;
	}
	
	Type visit(TypeofType t) {
		t.expression = pass.visit(t.expression);
		
		return t;
	}
	
	Type visit(IdentifierType t) {
		return t;
	}
	
	Type visit(PointerType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(SliceType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(FunctionType t) {
		t.returnType = visit(t.returnType);
		
		return t;
	}
	
	Type visit(AutoType t) {
		return t;
	}
}

