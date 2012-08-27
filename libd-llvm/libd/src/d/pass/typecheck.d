/**
 * This module crawl the AST to check types.
 * In the process unknown types are resolved
 * and type related operations are processed.
 */
module d.pass.typecheck;

import d.pass.base;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.dscope;
import d.ast.identifier;

import std.algorithm;
import std.array;

auto typeCheck(Module m) {
	auto pass = new TypecheckPass();
	
	return pass.visit(m);
}

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class TypecheckPass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	private TypeVisitor typeVisitor;
	private IdentifierVisitor identifierVisitor;
	private NamespaceVisitor namespaceVisitor;
	private SymbolResolver symbolResolver;
	
	private Scope currentScope;
	private Type returnType;
	
	private TypeSymbol thisSymbol;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		identifierVisitor	= new IdentifierVisitor(this);
		namespaceVisitor	= new NamespaceVisitor(this);
		symbolResolver		= new SymbolResolver(this);
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
	
	auto visit(Identifier i) {
		return identifierVisitor.resolve(i);
	}
	
	auto visit(Namespace ns) {
		return namespaceVisitor.visit(ns);
	}
}

import d.ast.adt;
import d.ast.dfunction;

class DeclarationVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Declaration visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Symbol visit(FunctionDefinition fun) {
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		scope(exit) returnType = oldReturnType;
		
		returnType = fun.returnType = pass.visit(fun.returnType);
		
		// Update scope.
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = fun.dscope;
		
		// And visit.
		pass.visit(fun.fbody);
		
		return fun;
	}
	
	Symbol visit(VariableDeclaration var) {
		var.value = pass.visit(var.value);
		
		final class ResolveType {
			Type visit(Type t) {
				return pass.visit(this.dispatch!(t => t)(t));
			}
			
			Type visit(AutoType t) {
				return var.value.type;
			}
		}
		
		var.type = (new ResolveType()).visit(var.type);
		var.value = buildImplicitCast(var.location, var.type, var.value);
		
		return var;
	}
	
	Declaration visit(FieldDeclaration f) {
		return visit(cast(VariableDeclaration) f);
	}
	
	Symbol visit(StructDefinition s) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = s.dscope;
		
		auto oldThisSymbol = thisSymbol;
		scope(exit) thisSymbol = oldThisSymbol;
		
		thisSymbol = s;
		
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
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(ExpressionStatement e) {
		pass.visit(e.expression);
	}
	
	void visit(DeclarationStatement d) {
		pass.visit(d.declaration);
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
		ifs.condition = buildExplicitCast(ifs.condition.location, new BooleanType(ifs.condition.location), pass.visit(ifs.condition));
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		w.condition = buildExplicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		w.condition = buildExplicitCast(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = f.dscope;
		
		f.condition = buildExplicitCast(f.condition.location, new BooleanType(f.condition.location), pass.visit(f.condition));
		f.increment = pass.visit(f.increment);
		
		visit(f.initialize);
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
		r.value = buildImplicitCast(r.location, returnType, pass.visit(r.value));
	}
}

import d.ast.expression;

class ExpressionVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
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
	
	Expression visit(CommaExpression ce) {
		ce.lhs = visit(ce.lhs);
		ce.rhs = visit(ce.rhs);
		
		ce.type = ce.rhs.type;
		
		return ce;
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		import std.algorithm;
		static if(find(["&&", "||"], operation)) {
			auto type = e.type;
			
			e.lhs = buildExplicitCast(e.lhs.location, type, e.lhs);
			e.rhs = buildExplicitCast(e.rhs.location, type, e.rhs);
		} else static if(find(["==", "!=", ">", ">=", "<", "<="], operation)) {
			auto type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = buildImplicitCast(e.lhs.location, type, e.lhs);
			e.rhs = buildImplicitCast(e.rhs.location, type, e.rhs);
		} else static if(find(["&", "|", "^", "+", "-", "*", "/", "%"], operation)) {
			e.type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = buildImplicitCast(e.lhs.location, e.type, e.lhs);
			e.rhs = buildImplicitCast(e.rhs.location, e.type, e.rhs);
		}
		
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
		
		e.type = e.expression.type;
		
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
		return buildExplicitCast(e.location, e.type, visit(e.expression));
	}
	
	Expression visit(CallExpression c) {
		c.arguments = c.arguments.map!(arg => visit(arg)).array();
		
		c.callee = visit(c.callee);
		
		// FIXME: get the right return type.
		if(typeid({ return c.type; }()) is typeid(AutoType)) {
			c.type = new IntegerType(c.type.location, IntegerOf!int);
		}
		
		return c;
	}
	
	Expression visit(IdentifierExpression ie) {
		auto resolved = pass.visit(ie.identifier);
		
		if(auto e = cast(Expression) resolved) {
			return visit(e);
		}
		
		assert(0, ie.identifier.name ~ " isn't an expression. It is a " ~ typeid({ return cast(Object) resolved; }()).toString());
	}
	
	Expression visit(FieldExpression fe) {
		fe.expression = visit(fe.expression);
		fe.type = pass.visit(fe.field.type);
		
		return fe;
	}
	
	Expression visit(MethodExpression me) {
		me.thisExpression = visit(me.thisExpression);
		me.type = pass.visit(me.method.returnType);
		
		return me;
	}
	
	Expression visit(ThisExpression te) {
		return te;
	}
	
	Expression visit(SymbolExpression e) {
		e.type = pass.visit(e.symbol.type);
		
		return e;
	}
	
	// Will be remove by cast operation.
	Expression visit(DefaultInitializer di) {
		return di;
	}
}

import d.ast.type;

class TypeVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Type visit(Type t) {
		return this.dispatch(t);
	}
	
	Type visit(IdentifierType it) {
		auto resolved = pass.visit(it.identifier);
		
		if(auto t = cast(Type) resolved) {
			return visit(t);
		}
		
		assert(0, it.identifier.name ~ " isn't an type.");
	}
	
	Type visit(SymbolType st) {
		return st;
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
	
	Type visit(TypeofType t) {
		t.expression = pass.visit(t.expression);
		
		return t.expression.type;
	}
}

import d.ast.base;

/**
 * Resolve identifiers as symbols
 */
class IdentifierVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Namespace resolve(Identifier i) {
		return this.dispatch(i);
	}
	
	Namespace visit(Identifier i) {
		return symbolResolver.resolve(i.location, currentScope.resolveWithFallback(i.location, i.name));
	}
	
	Namespace visit(QualifiedIdentifier qi) {
		return pass.visit(qi.namespace).resolve(qi.location, qi.name);
	}
}

/**
 * Resolve namespaces.
 */
class NamespaceVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Namespace visit(Namespace ns) {
		return this.dispatch(ns);
	}
	
	Namespace visit(Identifier i) {
		return pass.visit(i);
	}
	
	Namespace visit(ThisExpression e) {
		e.type = new SymbolType(e.location, thisSymbol);
		
		return e;
	}
}

/**
 * Resolve Symbol
 */
final class SymbolResolver {
	private TypecheckPass pass;
	alias pass this;
	
	private Location location;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Namespace resolve(Location newLocation, Symbol s) {
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = newLocation;
		
		return this.dispatch(s);
	}
	
	Namespace visit(FunctionDefinition fun) {
		return new SymbolExpression(location, fun);
	}
	
	Namespace visit(VariableDeclaration var) {
		return new SymbolExpression(location, var);
	}
	
	Namespace visit(FieldDeclaration f) {
		return new FieldExpression(location, new ThisExpression(location), f);
	}
	
	Namespace visit(StructDefinition sd) {
		return new SymbolType(location, sd);
	}
	
	Namespace visit(Parameter p) {
		return new SymbolExpression(location, p);
	}
	
	Namespace visit(AliasDeclaration a) {
		return a.type;
	}
}

import sdc.location;

private Expression buildCast(bool isExplicit = false)(Location location, Type type, Expression e) {
	// TODO: use struct to avoid memory allocation.
	final class CastFromBooleanType {
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Expression visit(BooleanType t) {
			return e;
		}
		
		Expression visit(IntegerType t) {
			return new PadExpression(location, type, e);
		}
	}
	
	final class CastFromIntegerType {
		Integer fromType;
		
		this(Integer fromType) {
			this.fromType = fromType;
		}
		
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		static if(isExplicit) {
			Expression visit(BooleanType t) {
				Expression zero = makeLiteral(location, 0);
				auto type = getPromotedType(location, e.type, zero.type);
				
				zero = buildImplicitCast(location, type, zero);
				e = buildImplicitCast(e.location, type, e);
				
				return new NotEqualityExpression(location, e, zero);
			}
		}
		
		Expression visit(IntegerType t) {
			if(fromType == t.type) {
				return e;
			} else if(t.type > fromType) {
				return new PadExpression(location, type, e);
			} else static if(isExplicit) {
				return new TruncateExpression(location, type, e);
			} else {
				import std.conv;
				assert(0, "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed");
			}
		}
	}
	
	final class CastFromFloatType {
		Float fromType;
		
		this(Float fromType) {
			this.fromType = fromType;
		}
		
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Expression visit(FloatType t) {
			if(fromType == t.type) {
				return e;
			} else {
				import std.conv;
				assert(0, "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed");
			}
		}
	}
	
	final class CastFromCharacterType {
		Character fromType;
		
		this(Character fromType) {
			this.fromType = fromType;
		}
		
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Expression visit(CharacterType t) {
			if(fromType == t.type) {
				return e;
			} else {
				import std.conv;
				assert(0, "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed");
			}
		}
	}
	
	final class Cast {
		Expression visit(Expression e) {
			return this.dispatch!(delegate Expression(Expression e) {
				return this.dispatch!(function Expression(Type t) {
					auto msg = typeid(t).toString() ~ " is not supported.";
					
					import sdc.terminal;
					outputCaretDiagnostics(t.location, msg);
					
					assert(0, msg);
				})(e.type);
			})(e);
		}
		
		Expression visit(DefaultInitializer di) {
			return type.initExpression(di.location);
		}
		
		Expression visit(BooleanType t) {
			return (new CastFromBooleanType()).visit(type);
		}
		
		Expression visit(IntegerType t) {
			return (new CastFromIntegerType(t.type)).visit(type);
		}
		
		Expression visit(FloatType t) {
			return (new CastFromFloatType(t.type)).visit(type);
		}
		
		Expression visit(CharacterType t) {
			return (new CastFromCharacterType(t.type)).visit(type);
		}
	}
	
	return (new Cast()).visit(e);
}

alias buildCast!false buildImplicitCast;
alias buildCast!true buildExplicitCast;

Type getPromotedType(Location location, Type t1, Type t2) {
	final class T2Handler {
		Integer t1type;
		
		this(Integer t1type) {
			this.t1type = t1type;
		}
		
		Type visit(Type t) {
			return this.dispatch(t);
		}
		
		Type visit(BooleanType t) {
			import std.algorithm;
			return new IntegerType(location, max(t1type, Integer.Int));
		}
		
		Type visit(IntegerType t) {
			import std.algorithm;
			// Type smaller than int are promoted to int.
			auto t2type = max(t.type, Integer.Int);
			return new IntegerType(location, max(t1type, t2type));
		}
	}
	
	final class T1Handler {
		Type visit(Type t) {
			return this.dispatch(t);
		}
		
		Type visit(BooleanType t) {
			return (new T2Handler(Integer.Int)).visit(t2);
		}
		
		Type visit(IntegerType t) {
			return (new T2Handler(t.type)).visit(t2);
		}
	}
	
	return (new T1Handler()).visit(t1);
}

