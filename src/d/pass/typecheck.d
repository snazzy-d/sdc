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
		declarationVisitor.variables.clear();
		
		class ParameterVisitor {
			void visit(Parameter p) {
				this.dispatch!((Parameter p){})(p);
			}
			
			void visit(NamedParameter p) {
				declarationVisitor.variables[p.name] = new VariableDeclaration(p.location, p.type, p.name, null);
			}
		}
		
		auto pv = new ParameterVisitor();
		
		foreach(p; fun.parameters) {
			pv.visit(p);
		}
		
		declarationVisitor.visit(fun);
	}
}

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
	
	Expression visit(IdentifierExpression ie) {
		ie.type = declarationVisitor.variables[ie.identifier.name].type;
		
		auto tid = typeid(declarationVisitor.variables[ie.identifier.name].type);
		
		return ie;
	}
	
	Expression visit(CastExpression e) {
		return buildExplicitCast(e.location, e.type, visit(e.expression));
	}
	
	Expression visit(CallExpression c) {
		// Do the appropriate thing.
		return c;
	}
}

import d.ast.type;
import sdc.location;

private Expression buildCast(bool isExplicit = false)(Location location, Type type, Expression e) {
	// TODO: make that a struct to avoid useless memory allocations.
	class CastToBuiltinType {
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
		
		Expression visit(IntegerType t) {
			if(t1type == t.type) {
				return e;
			} else if(t1type > t.type) {
				return new PadExpression(location, type, e);
			} else static if(isExplicit) {
				return new TruncateExpression(location, type, e);
			} else {
				import std.conv;
				assert(0, "implicit cast from " ~ to!string(t.type) ~ " to " ~ to!string(t1type) ~ " is not allowed");
			}
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
		
		Expression visit(IntegerType t) {
			return (new CastToBuiltinType(t.type)).visit(e);
		}
	}
	
	return (new CastFrom()).visit(type);
}

alias buildCast!false buildImplicitCast;
alias buildCast!true buildExplicitCast;

Type getPromotedType(Location location, Type t1, Type t2) {
	class T2Handler {
		Integer t1type;
		
		this(Integer t1type) {
			this.t1type = t1type;
		}
		
		Type visit(Type t) {
			return this.dispatch(t);
		}
		
		Type visit(IntegerType t) {
			import std.algorithm;
			return new IntegerType(location, max(t1type, t.type));
		}
	}
	
	class T1Handler {
		Type visit(Type t) {
			return this.dispatch(t);
		}
		
		Type visit(IntegerType t) {
			final switch(t.type) {
				case Integer.Bool, Integer.Byte, Integer.Ubyte, Integer.Short, Integer.Ushort, Integer.Int :
					return (new T2Handler(Integer.Int)).visit(t2);
					
				case Integer.Uint, Integer.Long, Integer.Ulong :
					return (new T2Handler(t.type)).visit(t2);
			}
		}
	}
	
	return (new T1Handler()).visit(t1);
}

