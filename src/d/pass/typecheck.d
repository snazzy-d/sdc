/**
 * This module crawl the AST to check types.
 * In the process unknown types are resolved
 * and type related operations are processed.
 */
module d.pass.typecheck;

import d.ast.dmodule;

Module typeCheck(Module m) {
	auto cg = new DeclarationVisitor();
	foreach(decl; m.declarations) {
		cg.visit(decl);
	}
	
	return m;
}

import util.visitor;

import d.ast.declaration;
import d.ast.dfunction;

class DeclarationVisitor {
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	
	VariableDeclaration[string] variables;
	
	this() {
		expressionVisitor = new ExpressionVisitor(this);
		statementVisitor = new StatementVisitor(this, expressionVisitor);
	}
	
final:
	void visit(Declaration d) {
		this.dispatch(d);
	}
	
	void visit(FunctionDefinition fun) {
		statementVisitor.visit(fun.fbody);
	}
	
	// TODO: this should be gone at this point (but isn't because flatten pass isn't implemented).
	void visit(VariablesDeclaration decls) {
		foreach(var; decls.variables) {
			visit(var);
		}
	}
	
	void visit(VariableDeclaration var) {
		var.value = buildImplicitCast(var.location, var.type, expressionVisitor.visit(var.value));
		
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
	
	void visit(IfStatement ifs) {
		ifs.condition = expressionVisitor.visit(ifs.condition);
		
		visit(ifs.then);
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
	
	Expression visit(IntegerLiteral!true il) {
		return il;
	}
	
	Expression visit(IntegerLiteral!false il) {
		return il;
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		import std.algorithm;
		static if(find(["&", "|", "^", "+", "-", "*", "/", "%"], operation)) {
			e.type = getPromotedType(e.lhs.type, e.rhs.type);
			
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
	
	Expression visit(IdentifierExpression ie) {
		ie.type = declarationVisitor.variables[ie.identifier.name].type;
		
		auto tid = typeid(declarationVisitor.variables[ie.identifier.name].type);
		
		return ie;
	}
	
	Expression visit(CastExpression e) {
		return buildExplicitCast(e.location, e.type, visit(e.expression));
	}
}

import d.ast.type;
import sdc.location;

private Expression buildCast(bool isExplicit = false)(Location location, Type type, Expression e) {
	// TODO: make that a struct to avoid useless memory allocations.
	class CastToBuiltinType(T) {
		Expression visit(Expression e) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(e.type);
		}
		
		private Expression handleBuiltinType(U)() {
			static if(is(U == T)) {
				// Casting to the same type is a noop.
				return e;
			} else static if(T.sizeof > U.sizeof) {
				// pad.
				return new PadExpression(location, type, e);
			} else static if(T.sizeof == U.sizeof) {
				throw new Exception("sign change is not supported");
			} else static if(is(T == bool)) {
				// Handle cast to bool
				throw new Exception("cast to bool is not supported");
			} else static if(isExplicit) {
				static assert(T.sizeof < U.sizeof);
				
				return new TruncateExpression(location, type, e);
			} else {
				assert(0, "implicit cast from " ~ U.stringof ~ " to " ~ T.stringof ~ " is not allowed");
			}
		}
		
		Expression visit(BuiltinType!bool) {
			return handleBuiltinType!bool();
		}
		
		Expression visit(BuiltinType!byte) {
			return handleBuiltinType!byte();
		}
		
		Expression visit(BuiltinType!ubyte) {
			return handleBuiltinType!ubyte();
		}
		
		Expression visit(BuiltinType!short) {
			return handleBuiltinType!short();
		}
		
		Expression visit(BuiltinType!ushort) {
			return handleBuiltinType!ushort();
		}
		
		Expression visit(BuiltinType!int) {
			return handleBuiltinType!int();
		}
		
		Expression visit(BuiltinType!uint) {
			return handleBuiltinType!uint();
		}
		
		Expression visit(BuiltinType!long) {
			return handleBuiltinType!long();
		}
		
		Expression visit(BuiltinType!ulong) {
			return handleBuiltinType!ulong();
		}
	}
	
	// dito
	class CastFrom {
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		private auto handleBuiltinType(T)() if(is(BuiltinType!T)) {
			return (new CastToBuiltinType!T()).visit(e);
		}
		
		Expression visit(BuiltinType!bool) {
			return handleBuiltinType!bool();
		}
		
		Expression visit(BuiltinType!byte) {
			return handleBuiltinType!byte();
		}
		
		Expression visit(BuiltinType!ubyte) {
			return handleBuiltinType!ubyte();
		}
		
		Expression visit(BuiltinType!short) {
			return handleBuiltinType!short();
		}
		
		Expression visit(BuiltinType!ushort) {
			return handleBuiltinType!ushort();
		}
		
		Expression visit(BuiltinType!int) {
			return handleBuiltinType!int();
		}
		
		Expression visit(BuiltinType!uint) {
			return handleBuiltinType!uint();
		}
		
		Expression visit(BuiltinType!long) {
			return handleBuiltinType!long();
		}
		
		Expression visit(BuiltinType!ulong) {
			return handleBuiltinType!ulong();
		}
	}
	
	return (new CastFrom()).visit(type);
}

alias buildCast!false buildImplicitCast;
alias buildCast!true buildExplicitCast;

Type getPromotedType(Type t1, Type t2) {
	auto location = t1.location;
	location.spanTo(t2.location);
	
	class T2Handler(T) {
		Type visit(Type t) {
			return this.dispatch!((Type t){ return new BuiltinType!T(location); })(t);
		}
		
		static if(T.sizeof <= uint.sizeof) {
			Type visit(BuiltinType!uint) {
				return new BuiltinType!uint(location);
			}
		}
		
		static if(T.sizeof < long.sizeof) {
			Type visit(BuiltinType!long) {
				return new BuiltinType!long(location);
			}
		}
		
		static if(T.sizeof <= long.sizeof) {
			Type visit(BuiltinType!ulong) {
				return new BuiltinType!ulong(location);
			}
		}
	}
	
	class T1Handler {
		Type visit(Type t) {
			return this.dispatch!((Type t){ return handleBuiltinType!int(); })(t);
		}
		
		private auto handleBuiltinType(T)() if(is(BuiltinType!T)) {
			return (new T2Handler!T()).visit(t2);
		}
		
		Type visit(BuiltinType!uint) {
			return handleBuiltinType!uint();
		}
		
		Type visit(BuiltinType!long) {
			return handleBuiltinType!long();
		}
		
		Type visit(BuiltinType!ulong) {
			return handleBuiltinType!ulong();
		}
	}
	
	return (new T1Handler()).visit(t1);
}

