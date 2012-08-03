/**
 * This module crawl the AST to check types.
 * In the process unknown types are resolved
 * and type related operations are processed.
 */
module d.pass.typecheck;

import d.ast.dmodule;

Module typeCheck(Module m) {
	auto dv = new DeclarationDefVisitor();
	foreach(decl; m.declarations) {
		dv.visit(decl);
	}
	
	return m;
}

import util.visitor;

import d.ast.declaration;
import d.ast.dfunction;

class DeclarationDefVisitor {
	private DeclarationVisitor declarationVisitor;
	
	this() {
		declarationVisitor  = new DeclarationVisitor();
	}
	
final:
	void visit(Declaration d) {
		this.dispatch(d);
	}
	
	void visit(FunctionDefinition fun) {
		declarationVisitor.visit(fun);
	}
}

class DeclarationVisitor {
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	
	VariableDeclaration[string] variables;
	Type returnType;
	
	this() {
		expressionVisitor = new ExpressionVisitor(this);
		statementVisitor = new StatementVisitor(this, expressionVisitor);
	}
	
final:
	void visit(Declaration d) {
		this.dispatch(d);
	}
	
	void visit(FunctionDefinition fun) {
		scope(exit) variables.clear();
		
		final class ParameterVisitor {
			void visit(Parameter p) {
				this.dispatch!((Parameter p){})(p);
			}
			
			void visit(NamedParameter p) {
				variables[p.name] = new VariableDeclaration(p.location, p.type, p.name, p.type.initExpression(p.location));
			}
		}
		
		auto pv = new ParameterVisitor();
		
		foreach(p; fun.parameters) {
			pv.visit(p);
		}
		
		returnType = fun.returnType;
		statementVisitor.visit(fun.fbody);
	}
	
	void visit(VariableDeclaration var) {
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
		
		variables[var.name] = var;
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
		ifs.condition = expressionVisitor.visit(ifs.condition);
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(ReturnStatement r) {
		r.value = buildImplicitCast(r.location, declarationVisitor.returnType, expressionVisitor.visit(r.value));
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
		
		import std.algorithm;
		static if(find(["&&", "||"], operation)) {
			auto type = e.type;
			
			e.lhs = buildExplicitCast(e.lhs.location, type, e.lhs);
			e.rhs = buildExplicitCast(e.rhs.location, type, e.rhs);
		} else static if(find(["==", "!="], operation)) {
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
	
	Expression visit(IdentifierExpression ie) {
		ie.type = declarationVisitor.variables[ie.identifier.name].type;
		
		return ie;
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
}

import d.ast.type;
import sdc.location;

private Expression buildCast(bool isExplicit = false)(Location location, Type type, Expression e) {
	// TODO: make that a struct to avoid useless memory allocations.
	final class CastToBooleanType {
		Expression visit(Expression e) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(e.type);
		}
		
		Expression visit(BooleanType t) {
			// Cast bool to bool is a noop.
			return e;
		}
		
		static if(isExplicit) {
			Expression visit(IntegerType t) {
				Expression zero = makeLiteral(location, 0);
				auto type = getPromotedType(location, e.type, zero.type);
				
				zero = buildImplicitCast(location, type, zero);
				e = buildImplicitCast(e.location, type, e);
				
				return new NotEqualityExpression(location, e, zero);
			}
		}
	}
	
	final class CastToIntegerType {
		Integer t1type;
		
		this(Integer t1type) {
			this.t1type = t1type;
		}
		
		Expression visit(Expression e) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(e.type);
		}
		
		Expression visit(BooleanType t) {
			return new PadExpression(location, type, e);
		}
		
		Expression visit(IntegerType t) {
			if(t1type == t.type) {
				return e;
			} else if(t1type > t.type) {
				return new PadExpression(location, type, e);
			} else static if(isExplicit) {
				return new TruncateExpression(location, type, e);
			} else {
				import std.conv;
				assert(0, "Implicit cast from " ~ to!string(t.type) ~ " to " ~ to!string(t1type) ~ " is not allowed");
			}
		}
	}
	
	final class CastToFloatType {
		Float t1type;
		
		this(Float t1type) {
			this.t1type = t1type;
		}
		
		Expression visit(Expression e) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(e.type);
		}
		
		Expression visit(FloatType t) {
			if(t1type == t.type) {
				return e;
			} else if(t1type > t.type) {
				return new PadExpression(location, type, e);
			} else static if(isExplicit) {
				return new TruncateExpression(location, type, e);
			} else {
				import std.conv;
				assert(0, "Implicit cast from " ~ to!string(t.type) ~ " to " ~ to!string(t1type) ~ " is not allowed");
			}
		}
	}
	
	final class CastToCharacterType {
		Character t1type;
		
		this(Character t1type) {
			this.t1type = t1type;
		}
		
		Expression visit(Expression e) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(e.type);
		}
		
		Expression visit(CharacterType t) {
			if(t1type == t.type) {
				return e;
			} else if(t1type > t.type) {
				return new PadExpression(location, type, e);
			} else static if(isExplicit) {
				return new TruncateExpression(location, type, e);
			} else {
				import std.conv;
				assert(0, "Implicit cast from " ~ to!string(t.type) ~ " to " ~ to!string(t1type) ~ " is not allowed");
			}
		}
	}
	
	final class CastTo {
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Expression visit(BooleanType t) {
			return (new CastToBooleanType()).visit(e);
		}
		
		Expression visit(IntegerType t) {
			return (new CastToIntegerType(t.type)).visit(e);
		}
		
		Expression visit(FloatType t) {
			return (new CastToFloatType(t.type)).visit(e);
		}
		
		Expression visit(CharacterType t) {
			return (new CastToCharacterType(t.type)).visit(e);
		}
	}
	
	return (new CastTo()).visit(type);
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

