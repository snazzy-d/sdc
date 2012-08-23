/**
 * Prepare scope for identifiers resolution.
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
	
	private Scope currentScope;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
	}
	
final:
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

import d.ast.dfunction;
import d.ast.dtemplate;

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
	
	Declaration visit(FunctionDefinition fun) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		foreach(p; fun.parameters) {
			currentScope.addSymbol(p);
		}
		
		pass.visit(fun.fbody);
		fun.dscope = currentScope;
		
		oldScope.addOverloadableSymbol(fun);
		
		return fun;
	}
	
	Declaration visit(VariableDeclaration var) {
		var.value = pass.visit(var.value);
		var.type = pass.visit(var.type);
		
		currentScope.addSymbol(var);
		
		return var;
	}
	
	Declaration visit(TemplateDeclaration tpl) {
		currentScope.addOverloadableSymbol(tpl);
		
		// No semantic is done on template declaration.
		return tpl;
	}
}

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
	
	void visit(DeclarationStatement d) {
		d.declaration = pass.visit(d.declaration);
	}
	
	void visit(ExpressionStatement e) {
		pass.visit(e.expression);
	}
	
	void visit(BlockStatement b) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		foreach(s; b.statements) {
			visit(s);
		}
		
		b.dscope = currentScope;
	}
	
	void visit(IfElseStatement ifs) {
		ifs.condition = pass.visit(ifs.condition);
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		visit(w.statement);
		
		w.condition = pass.visit(w.condition);
	}
	
	void visit(DoWhileStatement w) {
		visit(w.statement);
		
		w.condition = pass.visit(w.condition);
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = new NestedScope(oldScope);
		
		visit(f.initialize);
		visit(f.statement);
		
		f.condition = pass.visit(f.condition);
		f.increment = pass.visit(f.increment);
		
		f.dscope = pass.currentScope;
	}
	
	void visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
	}
}

class ExpressionVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	private IdentifierResolver identifierResolver;
	
	this(IdentifierPass pass) {
		this.pass = pass;
		
		identifierResolver = new IdentifierResolver();
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
		return new SymbolExpression(e.location, identifierResolver.resolve(e.identifier, currentScope));
	}
	
	Expression visit(DefaultInitializer i) {
		// Nothing to do, will go away at typecheck pass.
		return i;
	}
}

class TypeVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	this(IdentifierPass pass) {
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

/**
 * Resolve identifiers as symbols
 */
class IdentifierResolver {
	NamespaceVisitor namespaceVisitor;
	
	Scope s;
	
	this() {
		namespaceVisitor = new NamespaceVisitor();
	}
	
final:
	Symbol resolve(Identifier i, Scope newScope) {
		auto oldScope = s;
		scope(exit) s = oldScope;
		
		s = newScope;
		
		return this.dispatch(i);
	}
	
	Symbol visit(Identifier i) {
		return s.resolve(i.name);
	}
	
	Symbol visit(QualifiedIdentifier qi) {
		return namespaceVisitor.resolve(qi.namespace, s).resolve(qi.name);
	}
}

/**
 * Resolve namespaces's scope.
 */
class NamespaceVisitor {
	Scope s;
	
final:
	Scope resolve(Namespace ns, Scope newScope) {
		auto oldScope = s;
		scope(exit) s = oldScope;
		
		s = newScope;
		
		return this.dispatch(ns);
	}
}

