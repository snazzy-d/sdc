/**
 * Prepare scope for identifiers resolution.
 */
module d.pass.identifier;

import d.pass.base;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;

import std.algorithm;
import std.array;

auto resolveIdentifiers(Module m) {
	auto sv = new DeclarationVisitor();
	
	return sv.visit(m);
}

import d.ast.dfunction;

class DeclarationVisitor {
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	
	Scope currentScope;
	
	this() {
		expressionVisitor = new ExpressionVisitor(this);
		statementVisitor = new StatementVisitor(this, expressionVisitor);
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	// XXX: Ugly hack to preregister symbols.
	private void registerUnorderedDecls(Declaration[] decls) {
		foreach(decl; decls) {
			if(auto s = cast(Symbol) decl) {
				currentScope.addSymbol(s);
			}
		}
	}
	
	Module visit(Module m) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = m.dscope;
		
		registerUnorderedDecls(m.declarations);
		
		m.declarations = m.declarations.map!(d => visit(d)).array();
		
		return m;
	}
	
	Declaration visit(FunctionDefinition fun) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		foreach(p; fun.parameters) {
			currentScope.addSymbol(p);
		}
		
		statementVisitor.visit(fun.fbody);
		fun.dscope = currentScope;
		
		oldScope.addOverloadableSymbol(fun);
		
		return fun;
	}
	
	Declaration visit(VariableDeclaration var) {
		var.value = expressionVisitor.visit(var.value);
		
		currentScope.addSymbol(var);
		
		return var;
	}
}

import d.ast.statement;

class StatementVisitor {
	private DeclarationVisitor declarationVisitor;
	private ExpressionVisitor expressionVisitor;
	
	this(DeclarationVisitor declarationVisitor, ExpressionVisitor expressionVisitor) {
		this.declarationVisitor = declarationVisitor;
		this.expressionVisitor = expressionVisitor;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(DeclarationStatement d) {
		d.declaration = declarationVisitor.visit(d.declaration);
	}
	
	void visit(ExpressionStatement e) {
		expressionVisitor.visit(e.expression);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		ifs.condition = expressionVisitor.visit(ifs.condition);
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		visit(w.statement);
		
		w.condition = expressionVisitor.visit(w.condition);
	}
	
	void visit(DoWhileStatement w) {
		visit(w.statement);
		
		w.condition = expressionVisitor.visit(w.condition);
	}
	
	void visit(ForStatement f) {
		visit(f.initialize);
		visit(f.statement);
		
		f.condition = expressionVisitor.visit(f.condition);
		f.increment = expressionVisitor.visit(f.increment);
	}
	
	void visit(ReturnStatement r) {
		r.value = expressionVisitor.visit(r.value);
	}
}

import d.ast.expression;

class ExpressionVisitor {
	private DeclarationVisitor declarationVisitor;
	
	this(DeclarationVisitor declarationVisitor) {
		this.declarationVisitor = declarationVisitor;
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
		// TODO: resolve all kind of identifiers as appropriate expressions.
		return new SymbolExpression(e.location, declarationVisitor.currentScope.resolve(e.identifier.name));
	}
}

