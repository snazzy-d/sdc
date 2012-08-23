/**
 * This module crawl the AST to check types.
 * In the process unknown types are resolved
 * and type related operations are processed.
 */
module d.pass.typecheck;

import d.pass.base;

import d.ast.dmodule;

import std.algorithm;
import std.array;

auto typeCheck(Module m) {
	auto sv = new DeclarationVisitor();
	
	return sv.visit(m);
}

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.dscope;

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
	
	Module visit(Module m) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = m.dscope;
		
		foreach(decl; m.declarations) {
			visit(decl);
		}
		
		return m;
	}
	
	Symbol visit(FunctionDefinition fun) {
		auto oldScope = currentScope;
		scope(exit) currentScope = oldScope;
		
		currentScope = fun.dscope;
		
		// Prepare statement visitor for return type.
		auto oldReturnType = statementVisitor.returnType;
		scope(exit) statementVisitor.returnType = oldReturnType;
		
		statementVisitor.returnType = fun.returnType;
		
		// And visit.
		statementVisitor.visit(fun.fbody);
		
		return fun;
	}
	
	Symbol visit(VariableDeclaration var) {
		var.value = expressionVisitor.visit(var.value);
		
		final class ResolveType {
			Type visit(Type t) {
				return this.dispatch!(t => t)(t);
			}
			
			Type visit(AutoType t) {
				return var.value.type;
			}
			
			Type visit(TypeofType t) {
				t.expression = expressionVisitor.visit(t.expression);
				return t.expression.type;
			}
		}
		
		var.type = (new ResolveType()).visit(var.type);
		var.value = buildImplicitCast(var.location, var.type, var.value);
		
		return var;
	}
	
	Symbol visit(Parameter p) {
		return p;
	}
}

class DeclarationTypeResolver {
final:
	Type visit(Declaration d) {
		return this.dispatch(d);
	}
	
	Type visit(VariableDeclaration var) {
		return var.type;
	}
	
	Type visit(Parameter p) {
		return p.type;
	}
}

import d.ast.statement;

class StatementVisitor {
	private DeclarationVisitor declarationVisitor;
	private ExpressionVisitor expressionVisitor;
	
	private Type returnType;
	
	this(DeclarationVisitor declarationVisitor, ExpressionVisitor expressionVisitor) {
		this.declarationVisitor = declarationVisitor;
		this.expressionVisitor = expressionVisitor;
	}
	
final:
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(ExpressionStatement e) {
		expressionVisitor.visit(e.expression);
	}
	
	void visit(DeclarationStatement d) {
		declarationVisitor.visit(d.declaration);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		ifs.condition = buildExplicitCast(ifs.condition.location, new BooleanType(ifs.condition.location), expressionVisitor.visit(ifs.condition));
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		w.condition = buildExplicitCast(w.condition.location, new BooleanType(w.condition.location), expressionVisitor.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		w.condition = buildExplicitCast(w.condition.location, new BooleanType(w.condition.location), expressionVisitor.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		f.condition = buildExplicitCast(f.condition.location, new BooleanType(f.condition.location), expressionVisitor.visit(f.condition));
		f.increment = expressionVisitor.visit(f.increment);
		
		visit(f.initialize);
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
		// TODO: handle that by splitting symbol visitor.
		r.value = buildImplicitCast(r.location, returnType, expressionVisitor.visit(r.value));
	}
}

import d.ast.expression;

class ExpressionVisitor {
	private DeclarationVisitor declarationVisitor;
	private DeclarationTypeResolver declarationTypeResolver;
	
	this(DeclarationVisitor declarationVisitor) {
		this.declarationVisitor = declarationVisitor;
		
		this.declarationTypeResolver = new DeclarationTypeResolver();
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
		auto oldType = e.expression.type;
		
		e.expression = visit(e.expression);
		
		// If type as been update, we update the current expression type too.
		if(oldType !is e.expression.type) {
			e.type = e.expression.type;
		}
		
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
		foreach(i, arg; c.arguments) {
			c.arguments[i] = visit(arg);
		}
		
		//FIXME: get the right type.
		if(typeid({ return c.type; }()) is typeid(AutoType)) {
			c.type = new IntegerType(c.type.location, IntegerOf!int);
		}
		
		return c;
	}
	
	Expression visit(SymbolExpression e) {
		e.type = declarationTypeResolver.visit(e.symbol);
		
		return e;
	}
	
	// Will be remove by cast operation.
	Expression visit(DefaultInitializer di) {
		return di;
	}
}

import d.ast.type;
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

