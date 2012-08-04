module d.pass.identifier;

import d.pass.base;

import d.ast.symbol;

auto resolveIdentifiers(ModuleSymbol m) {
	auto sv = new SymbolVisitor();
	
	return sv.visit(m);
}

import d.ast.dfunction;

class SymbolVisitor {
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	
	ScopeSymbol parent;
	
	this() {
		expressionVisitor = new ExpressionVisitor(this);
		statementVisitor = new StatementVisitor(this, expressionVisitor);
	}
	
final:
	Symbol visit(Symbol s) {
		return this.dispatch(s);
	}
	
	ModuleSymbol visit(ModuleSymbol m) {
		parent = m;
		
		foreach(sym; m.symbols) {
			visit(sym);
		}
		
		return m;
	}
	
	Symbol visit(FunctionSymbol fun) {
		auto oldParent = parent;
		scope(exit) parent = oldParent;
		
		parent = fun;
		
		statementVisitor.visit(fun.fbody);
		
		return fun;
	}
	
	Symbol visit(VariableSymbol var) {
		var.value = expressionVisitor.visit(var.value);
		
		return var;
	}
}

import d.ast.statement;

class StatementVisitor {
	private SymbolVisitor symbolVisitor;
	private ExpressionVisitor expressionVisitor;
	
	this(SymbolVisitor symbolVisitor, ExpressionVisitor expressionVisitor) {
		this.symbolVisitor = symbolVisitor;
		this.expressionVisitor = expressionVisitor;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(ExpressionStatement e) {
		expressionVisitor.visit(e.expression);
	}
	
	void visit(SymbolStatement s) {
		symbolVisitor.visit(s.symbol);
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
	
	void visit(ReturnStatement r) {
		r.value = expressionVisitor.visit(r.value);
	}
}

import d.ast.expression;

class ExpressionVisitor {
	private SymbolVisitor symbolVisitor;
	
	this(SymbolVisitor symbolVisitor) {
		this.symbolVisitor = symbolVisitor;
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
		foreach(i, arg; c.arguments) {
			c.arguments[i] = visit(arg);
		}
		
		return c;
	}
	
	Expression visit(IdentifierExpression e) {
		// TODO: check for staticness and create a global variable read if appropriate.
		return new SymbolExpression(e.location, symbolVisitor.parent.s.resolve(e.identifier.name));
	}
}

