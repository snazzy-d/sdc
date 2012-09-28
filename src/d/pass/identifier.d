/**
 * This module crawl the AST to resolve identifiers.
 */
module d.pass.identifier;

import d.pass.base;

import d.pass.dscope;

import d.ast.dmodule;
import d.ast.dscope;
import d.ast.identifier;

import std.algorithm;
import std.array;

auto resolveIdentifiers(Module m) {
	auto pass = new IdentifierPass();
	
	import d.pass.flatten;
	return pass.visit(flatten(m));
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
	private IdentifierVisitor identifierVisitor;
	
	private TypeDotIdentifierVisitor typeDotIdentifierVisitor;
	private ExpressionDotIdentifierVisitor expressionDotIdentifierVisitor;
	
	private TemplateInstanciationDotIdentifierVisitor templateInstanciationDotIdentifierVisitor;
	
	private SymbolInTypeResolver symbolInTypeResolver;
	
	private ScopePass scopePass;
	
	private Scope currentScope;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		identifierVisitor	= new IdentifierVisitor(this);
		
		typeDotIdentifierVisitor		= new TypeDotIdentifierVisitor(this);
		expressionDotIdentifierVisitor	= new ExpressionDotIdentifierVisitor(this);
		
		templateInstanciationDotIdentifierVisitor	= new TemplateInstanciationDotIdentifierVisitor(this);
		
		symbolInTypeResolver	= new SymbolInTypeResolver(this);
		
		scopePass = new ScopePass();
	}
	
final:
	Module visit(Module m) {
		m = scopePass.visit(m);
		
		auto name = m.moduleDeclaration.name;
		
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = m.dscope;
		
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
	
	auto visit(Identifier i) {
		return identifierVisitor.visit(i);
	}
	
	auto visit(TemplateInstance tpl) {
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = tpl.dscope;
		
		tpl.declarations = tpl.declarations.map!(d => visit(d)).array();
		
		return tpl;
	}
}

import d.ast.adt;
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
	
	Symbol visit(FunctionDeclaration d) {
		d.returnType = pass.visit(d.returnType);
		
		d.parameters = d.parameters.map!(p => visit(p)).array();
		
		return d;
	}
	
	Symbol visit(FunctionDefinition d) {
		d.returnType = pass.visit(d.returnType);
		
		d.parameters = d.parameters.map!(p => visit(p)).array();
		
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope;
		
		// And visit.
		pass.visit(d.fbody);
		
		return d;
	}
	
	Symbol visit(VariableDeclaration var) {
		var.type = pass.visit(var.type);
		var.value = pass.visit(var.value);
		
		return var;
	}
	
	Declaration visit(FieldDeclaration f) {
		return visit(cast(VariableDeclaration) f);
	}
	
	Symbol visit(StructDefinition d) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = d.dscope;
		
		d.members = d.members.map!(m => visit(m)).array();
		
		return d;
	}
	
	Parameter visit(Parameter p) {
		p.type = pass.visit(p.type);
		
		return p;
	}
	
	Symbol visit(AliasDeclaration a) {
		a.type = pass.visit(a.type);
		
		return a;
	}
	
	Declaration visit(TemplateDeclaration tpl) {
		// No semantic is done on template declarations.
		return tpl;
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
	
	Expression visit(StringLiteral e) {
		return e;
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
		auto resolved = pass.visit(e.identifier);
		
		if(auto asExpr = cast(Expression) resolved) {
			return asExpr;
		}
		
		assert(0, e.identifier.name ~ " isn't an expression.");
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
	
	Expression visit(IndexExpression e) {
		e.indexed = visit(e.indexed);
		
		e.parameters = e.parameters.map!(e => visit(e)).array();
		
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
		auto resolved = pass.visit(t.identifier);
		
		if(auto asType = cast(Type) resolved) {
			return asType;
		}
		
		assert(0, t.identifier.name ~ " isn't a type.");
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
	
	Type visit(SliceType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(AutoType t) {
		return t;
	}
}

import d.ast.base;
import d.pass.util;

/**
 * Resolve identifier as type or expression.
 */
class IdentifierVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	private Location location;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Identifiable visit(Identifier i) {
		return this.dispatch(i);
	}
	
	Identifiable visit(BasicIdentifier i) {
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = i.location;
		
		return visit(currentScope.resolveWithFallback(i.name));
	}
	
	Identifiable visit(ExpressionDotIdentifier i) {
		i.expression = pass.visit(i.expression);
		
		return expressionDotIdentifierVisitor.visit(i);
	}
	
	Identifiable visit(TypeDotIdentifier i) {
		i.type = pass.visit(i.type);
		
		return typeDotIdentifierVisitor.visit(i);
	}
	
	Identifiable visit(IdentifierDotIdentifier i) {
		auto resolved = visit(i.identifier);
		
		if(auto t = cast(Type) resolved) {
			return typeDotIdentifierVisitor.visit(new TypeDotIdentifier(i.location, i.name, t));
		} else if(auto e = cast(Expression) resolved) {
			return expressionDotIdentifierVisitor.visit(new ExpressionDotIdentifier(i.location, i.name, e));
		} else {
			assert(0, "type or expression expected.");
		}
	}
	
	Identifiable visit(AmbiguousDotIdentifier i) {
		if(auto type = pass.visit(i.qualifier.type)) {
			return visit(new TypeDotIdentifier(i.location, i.name, type));
		} else if(auto expression = pass.visit(i.qualifier.expression)) {
			return visit(new ExpressionDotIdentifier(i.location, i.name, expression));
		}
		
		assert(0, "Ambiguous can't be deambiguated.");
	}
	
	Identifiable visit(TemplateInstanciationDotIdentifier i) {
		return templateInstanciationDotIdentifierVisitor.resolve(i);
	}
	
	// Symbols resolvers.
	Identifiable visit(Symbol s) {
		return this.dispatch(s);
	}
	
	Identifiable visit(StructDefinition sd) {
		return new SymbolType(location, sd);
	}
	
	Identifiable visit(AliasDeclaration a) {
		return new SymbolType(location, a);
	}
	
	Identifiable visit(TypeTemplateParameter p) {
		return new SymbolType(location, p);
	}
	
	Identifiable visit(FunctionDeclaration fun) {
		return new SymbolExpression(location, fun);
	}
	
	Identifiable visit(FunctionDefinition fun) {
		return new SymbolExpression(location, fun);
	}
	
	Identifiable visit(VariableDeclaration var) {
		return new SymbolExpression(location, var);
	}
	
	Identifiable visit(FieldDeclaration f) {
		return new FieldExpression(location, new ThisExpression(location), f);
	}
	
	Identifiable visit(Parameter p) {
		return new SymbolExpression(location, p);
	}
}

/**
 * Resolve type.identifier as type or expression.
 */
class TypeDotIdentifierVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Identifiable visit(TypeDotIdentifier i) {
		if(Symbol s = symbolInTypeResolver.resolve(i.type, i.name)) {
			if(auto ts = cast(TypeSymbol) s) {
				return new SymbolType(i.location, ts);
			} else if(auto es = cast(ExpressionSymbol) s) {
				return new SymbolExpression(i.location, es);
			} else {
				assert(0, "what the hell is that symbol ???");
			}
		}
		
		switch(i.name) {
			case "init" :
				return i.type.initExpression(i.location);
			
			case "sizeof" :
				return new SizeofExpression(i.location, i.type);
			
			default :
				assert(0, i.name ~ " can't be resolved in type.");
		}
	}
}

/**
 * Resolve expression.identifier as type or expression.
 */
class ExpressionDotIdentifierVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	private Location location;
	private Expression expression;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Expression visit(ExpressionDotIdentifier i) {
		return resolveOrDefer!(function bool(Expression e) {
			return e.type !is null;
		}, delegate Expression(Expression e) {
			auto oldLocation = location;
			scope(exit) location = oldLocation;
			
			location = i.location;
			
			auto oldExpression = expression;
			scope(exit) expression = oldExpression;
			
			expression = e;
			
			if(auto s = pass.symbolInTypeResolver.resolve(e.type, i.name)) {
				return this.dispatch!((s) {
					auto resolved = pass.identifierVisitor.visit(s);
				
					if(auto asExpr = cast(Expression) resolved) {
						return new CommaExpression(i.location, e, asExpr);
					}
				
					assert(0, "Don't know what to do with that !");
				})(s);
			} else if(auto asExpr = cast(Expression) pass.typeDotIdentifierVisitor.visit(new TypeDotIdentifier(i.location, i.name, e.type))) {
				// expression.sizeof or similar stuffs.
				return new CommaExpression(i.location, e, asExpr);
			}
			
			assert(0, "Can't resolve identifier.");
		})(i.location, i.expression);
	}
	
	Expression visit(FieldDeclaration f) {
		return new FieldExpression(location, expression, f);
	}
	
	Expression visit(FunctionDefinition f) {
		return new MethodExpression(location, expression, f);
	}
}

/**
 * Resolve identifier!(arguments).identifier as type or expression.
 */
class TemplateInstanciationDotIdentifierVisitor {
	private IdentifierPass pass;
	alias pass this;
	
	private Location location;
	private Expression expression;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Identifiable resolve(TemplateInstanciationDotIdentifier i) {
		auto tplDecl = this.dispatch(i.templateInstanciation.identifier);
		
		auto tplArgs = i.templateInstanciation.arguments;
		
		// FIXME: mangling is not always possible at this point. Delay to mangling pass if it make sense.
		import d.pass.mangle;
		auto mangler = new TypeMangler(null);
		
		string id = tplArgs.map!(delegate string(TemplateArgument arg) { return "T" ~ mangler.visit((cast(TypeTemplateArgument) arg).type); }).join();
		
		import d.pass.clone;
		auto clone = new ClonePass();
		
		auto instance = tplDecl.instances.get(id, tplDecl.instances[id] = pass.visit(scopePass.visit(new TemplateInstance(location, tplArgs, tplDecl.declarations.map!(delegate Declaration(Declaration d) { return clone.visit(d); }).array()), tplDecl)));
		
		// TODO: handle type.template and expression.template
		return identifierVisitor.visit(instance.dscope.resolve(i.name));
	}
	
	TemplateDeclaration visit(BasicIdentifier i) {
		return cast(TemplateDeclaration) currentScope.resolveWithFallback(i.name);
	}
}

/**
 * Resolve symbols in types.
 */
class SymbolInTypeResolver {
	private IdentifierPass pass;
	alias pass this;
	
	private string name;
	
	this(IdentifierPass pass) {
		this.pass = pass;
	}
	
final:
	Symbol resolve(Type t, string newName) {
		auto oldName = name;
		scope(exit) name = oldName;
		
		name = newName;
		
		return visit(t);
	}
	
	Symbol visit(Type t) {
		return this.dispatch(t);
	}
	
	Symbol visit(IntegerType t) {
		return null;
	}
	
	Symbol visit(SliceType t) {
		switch(name) {
			case "length" :
				auto lt = new IntegerType(t.location, Integer.Ulong);
				return new FieldDeclaration(new VariableDeclaration(t.location, lt, "length", new DefaultInitializer(lt)), 0);
			
			case "ptr" :
				auto pt = new PointerType(t.location, t.type);
				return new FieldDeclaration(new VariableDeclaration(t.location, pt, "ptr", new DefaultInitializer(pt)), 1);
			
			default :
				assert(0, name ~ " isn't a slice property.");
		}
	}
	
	Symbol visit(SymbolType t) {
		return this.dispatch(t.symbol);
	}
	
	Symbol visit(AliasDeclaration a) {
		return visit(a.type);
	}
	
	Symbol visit(StructDefinition s) {
		return s.dscope.resolve(name);
	}
}

