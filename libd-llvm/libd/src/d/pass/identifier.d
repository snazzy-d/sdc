/**
 * This module crawl the AST to resolve identifiers.
 */
module d.pass.identifier;

import d.pass.base;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.identifier;

import std.algorithm;
import std.array;

auto resolveIdentifiers(Module m) {
	auto pass = new IdentifierPass();
	
	return pass.visit(m);
}

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class IdentifierPass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	private TypeVisitor typeVisitor;
	private IdentifierTypeVisitor identifierTypeVisitor;
	private IdentifierExpressionVisitor identifierExpressionVisitor;
	
	private Scope currentScope;
	
	this() {
		declarationVisitor			= new DeclarationVisitor(this);
		statementVisitor			= new StatementVisitor(this);
		expressionVisitor			= new ExpressionVisitor(this);
		typeVisitor					= new TypeVisitor(this);
		identifierTypeVisitor		= new IdentifierTypeVisitor(this);
		identifierExpressionVisitor	= new IdentifierExpressionVisitor(this);
	}
	
final:
	Module visit(Module m) {
		foreach(decl; m.declarations) {
			visit(decl);
		}
		
		return m;
	}
	
	auto visit(Declaration decl) {
		return declarationVisitor.visit(decl);
	}
	
	auto visit(Statement stmt) {
		return statementVisitor.visit(stmt);
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

class DeclarationVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Symbol visit(FunctionDefinition fun) {
		fun.returnType = pass.visit(fun.returnType);
		
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = fun.dscope;
		
		// And visit.
		pass.visit(fun.fbody);
		
		return fun;
	}
	
	Symbol visit(VariableDeclaration var) {
		var.type = pass.visit(var.type);
		var.value = pass.visit(var.value);
		
		return var;
	}
	
	Declaration visit(FieldDeclaration f) {
		return visit(cast(VariableDeclaration) f);
	}
	
	Symbol visit(StructDefinition s) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = s.dscope;
		
		s.members = s.members.map!(m => visit(m)).array();
		
		return s;
	}
	
	Symbol visit(Parameter p) {
		return p;
	}
	
	Symbol visit(AliasDeclaration a) {
		return a;
	}
}

import d.ast.statement;

class StatementVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(ExpressionStatement e) {
		e.expression = pass.visit(e.expression);
	}
	
	void visit(DeclarationStatement d) {
		d.declaration = pass.visit(d.declaration);
	}
	
	void visit(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = b.dscope;
		
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		ifs.condition = pass.visit(ifs.condition);
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		w.condition = pass.visit(w.condition);
		
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		w.condition = pass.visit(w.condition);
		
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = f.dscope;
		
		visit(f.initialize);
		
		f.condition = pass.visit(f.condition);
		f.increment = pass.visit(f.increment);
		
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
	}
}

import d.ast.expression;

class ExpressionVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	this(IdentifierPass pass) {
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
	
	Expression visit(CommaExpression e) {
		return handleBinaryExpression(e);
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
	
	private auto handleCastExpression(CastType T)(CastUnaryExpression!T e) {
		e.type = pass.visit(e.type);
		
		return handleUnaryExpression(e);
	}
	
	Expression visit(CastExpression e) {
		return handleCastExpression(e);
	}
	
	Expression visit(CallExpression e) {
		e.arguments = e.arguments.map!(arg => visit(arg)).array();
		
		e.callee = visit(e.callee);
		
		return e;
	}
	
	Expression visit(IdentifierExpression e) {
		return identifierExpressionVisitor.visit(e.identifier);
	}
	
	Expression visit(FieldExpression e) {
		e.expression = visit(e.expression);
		
		return e;
	}
	
	Expression visit(MethodExpression e) {
		e.thisExpression = visit(e.thisExpression);
		
		return e;
	}
	
	Expression visit(ThisExpression e) {
		return e;
	}
	
	Expression visit(SymbolExpression e) {
		return e;
	}
	
	Expression visit(DefaultInitializer di) {
		return di;
	}
}

import d.ast.type;

class TypeVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Type visit(Type t) {
		return this.dispatch(t);
	}
	
	Type visit(IdentifierType t) {
		return identifierTypeVisitor.visit(t.identifier);
	}
	
	Type visit(SymbolType t) {
		return t;
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
	
	Type visit(PointerType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(AutoType t) {
		return t;
	}
}

import d.ast.base;

/**
 * Resolve identifiers as expressions.
 */
class IdentifierVisitor(T) if(is(T == Expression) || is(T == Type)) {
	private IdentifierPass pass;
	alias pass this;
	
	private Location location;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	T visit(Identifier i) {
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = i.location;
		
		return visit(currentScope.resolveWithFallback(i.name));
	}
	
	T visit(Symbol s) {
		return this.dispatch(s);
	}
	
	static if(is(T : Type)) {
		T visit(StructDefinition sd) {
			return new SymbolType(location, sd);
		}
		
		T visit(AliasDeclaration a) {
			return new SymbolType(location, a);
		}
	} else {
		T visit(FunctionDefinition fun) {
			return new SymbolExpression(location, fun);
		}
		
		T visit(VariableDeclaration var) {
			return new SymbolExpression(location, var);
		}
		
		T visit(FieldDeclaration f) {
			return new FieldExpression(location, new ThisExpression(location), f);
		}
		
		T visit(Parameter p) {
			return new SymbolExpression(location, p);
		}
	}
}

alias IdentifierVisitor!Type IdentifierTypeVisitor;
alias IdentifierVisitor!Expression IdentifierExpressionVisitor;

