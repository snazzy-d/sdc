/**
 * This module crawl the AST to check types.
 * In the process unknown types are resolved
 * and type related operations are processed.
 */
module d.pass.typecheck;

import d.pass.base;

import d.ast.dmodule;
import d.ast.dscope;

import std.algorithm;
import std.array;
import std.range;

import d.ast.expression;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

class TypecheckPass {
	private DeclarationVisitor declarationVisitor;
	private StatementVisitor statementVisitor;
	private ExpressionVisitor expressionVisitor;
	private TypeVisitor typeVisitor;
	
	private DefaultInitializerVisitor defaultInitializerVisitor;
	
	private SizeofCalculator sizeofCalculator;
	
	private Type returnType;
	private Type thisType;
	
	private Type[ExpressionSymbol] symbolTypes;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		
		defaultInitializerVisitor = new DefaultInitializerVisitor(this);
		
		sizeofCalculator	= new SizeofCalculator(this);
	}
	
final:
	Module[] visit(Module[] modules) {
		import d.pass.identifier;
		auto identifierPass = new IdentifierPass();
		
		modules = identifierPass.visit(modules);
		
		// Set reference to null to allow garbage collection.
		identifierPass = null;
		
		return modules.map!(m => visit(m)).array();
	}
	
	private Module visit(Module m) {
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

import d.ast.adt;
import d.ast.dfunction;
import d.ast.dtemplate;

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
	
	Symbol visit(FunctionDeclaration d) {
		d.returnType = pass.visit(d.returnType);
		
		d.type = new FunctionType(d.location, d.returnType, d.parameters, false);
		
		symbolTypes[d] = d.type;
		
		return d;
	}
	
	Symbol visit(FunctionDefinition d) {
		d.parameters = d.parameters.map!(p => this.dispatch(p)).array();
		
		if(typeid({ return d.returnType; }()) !is typeid(AutoType)) {
			d.returnType = pass.visit(d.returnType);
		}
		
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		scope(exit) returnType = oldReturnType;
		
		returnType = d.returnType;
		
		// TODO: move that into an ADT pass.
		// If it isn't a static method, add this.
		if(!d.isStatic) {
			auto thisParameter = new Parameter(d.location, "this", thisType);
			thisParameter.isReference = true;
			
			d.parameters = thisParameter ~ d.parameters;
		}
		
		// And visit.
		pass.visit(d.fbody);
		
		if(typeid({ return d.returnType; }()) is typeid(AutoType)) {
			d.returnType = returnType;
		}
		
		d.type = new FunctionType(d.location, d.returnType, d.parameters, false);
		
		symbolTypes[d] = d.type;
		
		return d;
	}
	
	Symbol visit(VariableDeclaration var) {
		var.value = pass.visit(var.value);
		
		// If the type is infered, then we use the type of the value.
		if(typeid({ return var.type; }()) is typeid(AutoType)) {
			var.type = var.value.type;
		} else {
			var.type = pass.visit(var.type);
			var.value = buildImplicitCast(var.location, var.type, var.value);
		}
		
		symbolTypes[var] = var.type;
		
		return var;
	}
	
	Declaration visit(FieldDeclaration f) {
		return visit(cast(VariableDeclaration) f);
	}
	
	Symbol visit(StructDefinition s) {
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(s.location, s);
		
		s.members = s.members.map!(m => visit(m)).array();
		
		return s;
	}
	
	Parameter visit(Parameter p) {
		symbolTypes[p] = p.type = pass.visit(p.type);
		
		return p;
	}
	
	Symbol visit(AliasDeclaration a) {
		a.type = pass.visit(a.type);
		
		return a;
	}
	
	Symbol visit(TemplateDeclaration tpl) {
		foreach(instance; tpl.instances) {
			instance.declarations = instance.declarations.map!(d => visit(d)).array();
		}
		
		// No semantic is done on templates declarations.
		return tpl;
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
		e.expression = pass.visit(e.expression);
	}
	
	void visit(DeclarationStatement d) {
		d.declaration = pass.visit(d.declaration);
	}
	
	void visit(BlockStatement b) {
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
		visit(f.initialize);
		
		f.condition = buildExplicitCast(f.condition.location, new BooleanType(f.condition.location), pass.visit(f.condition));
		f.increment = pass.visit(f.increment);
		
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
		
		if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
			returnType = r.value.type;
		} else {
			r.value = buildImplicitCast(r.location, returnType, r.value);
		}
	}
}

import d.ast.expression;
import d.pass.util;

class ExpressionVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Expression visit(Expression e) out(result) {
		if(!result.type) {
			auto msg = "Type should have been set for expression " ~ typeid(result).toString() ~ " at this point.";
			
			import sdc.terminal;
			outputCaretDiagnostics(result.location, msg);
			
			assert(0, msg);
		}
	} body {
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
	
	Expression visit(CommaExpression ce) {
		ce.lhs = visit(ce.lhs);
		ce.rhs = visit(ce.rhs);
		
		ce.type = ce.rhs.type;
		
		return ce;
	}
	
	Expression visit(AssignExpression e) {
		e.lhs = visit(e.lhs);
		e.type = e.lhs.type;
		
		e.rhs = buildImplicitCast(e.rhs.location, e.type, visit(e.rhs));
		
		return e;
	}
	
	private auto handleArithmeticExpression(string operation)(BinaryExpression!operation e) if(find(["+", "-"], operation)) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		if(auto pointerType = cast(PointerType) e.lhs.type) {
			return visit(new AddressOfExpression(e.location, new IndexExpression(e.location, e.lhs, [e.rhs])));
		}
		
		e.type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
		
		e.lhs = buildImplicitCast(e.lhs.location, e.type, e.lhs);
		e.rhs = buildImplicitCast(e.rhs.location, e.type, e.rhs);
		
		return e;
	}
	
	Expression visit(AddExpression e) {
		return handleArithmeticExpression(e);
	}
	
	Expression visit(SubExpression e) {
		return handleArithmeticExpression(e);
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		import std.algorithm;
		static if(find(["&&", "||"], operation)) {
			e.type = new BooleanType(e.location);
			
			e.lhs = buildExplicitCast(e.lhs.location, e.type, e.lhs);
			e.rhs = buildExplicitCast(e.rhs.location, e.type, e.rhs);
		} else static if(find(["==", "!=", ">", ">=", "<", "<="], operation)) {
			auto type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = buildImplicitCast(e.lhs.location, type, e.lhs);
			e.rhs = buildImplicitCast(e.rhs.location, type, e.rhs);
			
			e.type = new BooleanType(e.location);
		} else static if(find(["&", "|", "^", "*", "/", "%"], operation)) {
			e.type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = buildImplicitCast(e.lhs.location, e.type, e.lhs);
			e.rhs = buildImplicitCast(e.rhs.location, e.type, e.rhs);
		} else static if(find([","], operation)) {
			e.type = e.rhs.type;
		}
		
		return e;
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
	
	private Expression handleIncrementExpression(UnaryExpression)(UnaryExpression e) {
		e.expression = visit(e.expression);
		e.type = e.expression.type;
		
		if(auto pointerType = cast(PointerType) e.expression.type) {
			return e;
		} else if(auto integerType = cast(IntegerType) e.expression.type) {
			return e;
		}
		
		assert(false, "Increment and decrement are performed on integers or pointer types.");
	}
	
	Expression visit(PreIncrementExpression e) {
		return handleIncrementExpression(e);
	}
	
	Expression visit(PreDecrementExpression e) {
		return handleIncrementExpression(e);
	}
	
	Expression visit(PostIncrementExpression e) {
		return handleIncrementExpression(e);
	}
	
	Expression visit(PostDecrementExpression e) {
		return handleIncrementExpression(e);
	}
	
	Expression visit(AddressOfExpression e) {
		assert(typeid({ return e.expression; }()) !is typeid(AddressOfExpression), "Cannot take the address of an address.");
		
		e.expression = visit(e.expression);
		
		// For fucked up reasons, &funcname is a special case.
		if(auto asSym = cast(SymbolExpression) e.expression) {
			if(auto asDecl = cast(FunctionDeclaration) asSym.symbol) {
				return e.expression;
			}
		}
		
		e.type = new PointerType(e.location, e.expression.type);
		
		return e;
	}
	
	Expression visit(DereferenceExpression e) {
		e.expression = visit(e.expression);
		
		// TODO: handle function dereference.
		if(auto pt = cast(PointerType) e.expression.type) {
			e.type = pt.type;
			
			return e;
		}
		
		assert(0, typeid({ return e.expression.type; }()).toString() ~ " is not a pointer type.");
	}
	
	Expression visit(CastExpression e) {
		return buildExplicitCast(e.location, pass.visit(e.type), visit(e.expression));
	}
	
	Expression visit(CallExpression c) {
		auto callee = visit(c.callee);
		
		// XXX: is it the appropriate place to perform that ?
		if(auto me = cast(MethodExpression) callee) {
			callee = visit(new SymbolExpression(me.location, me.method));
			c.arguments = visit(me.thisExpression) ~ c.arguments;
		}
		
		auto type = cast(FunctionType) callee.type;
		assert(type, "You must call function, you fool !!!");
		foreach(ref arg, ref param; lockstep(c.arguments, type.parameters)) {
			arg = buildImplicitCast(arg.location, param.type, pass.visit(arg));
		}
		
		c.callee = callee;
		c.type = type.returnType;
		
		return c;
	}
	
	Expression visit(FieldExpression fe) {
		fe.expression = visit(fe.expression);
		
		// XXX: can't this be visited before ?
		fe.type = pass.visit(fe.field.type);
		
		return fe;
	}
	
	Expression visit(MethodExpression me) {
		me.thisExpression = visit(me.thisExpression);
		
		// XXX: can't this be visited before ?
		me.type = pass.visit(me.method.returnType);
		
		return me;
	}
	
	Expression visit(ThisExpression e) {
		e.type = thisType;
		
		return e;
	}
	
	Expression visit(SymbolExpression e) {
		return resolveOrDefer!(delegate bool(Expression cause) {
			// Too restrictive for now.
			// return (e.symbol in pass.symbolTypes) !is null;
			
			return typeid({ return e.symbol.type; }()) !is typeid(AutoType);
		}, delegate Expression(Expression cause) {
			// ditto
			// e.type = pass.symbolTypes[e.symbol];
			
			e.type = e.symbol.type;
			
			return e;
		})(e.location, e);
	}
	
	Expression visit(IndexExpression e) {
		// TODO: check if it is valid.
		e.indexed = visit(e.indexed);
		
		if(auto asSlice = cast(SliceType) e.indexed.type) {
			e.type = asSlice.type;
		} else if(auto asPointer = cast(PointerType) e.indexed.type) {
			e.type = asPointer.type;
		} else if(auto asStaticArray = cast(StaticArrayType) e.indexed.type) {
			e.type = asStaticArray.type;
		}
		
		assert(e.type, "Can't index " ~ typeid({ return e.indexed; }()).toString());
		
		e.parameters = e.parameters.map!(e => visit(e)).array();
		
		return e;
	}
	
	Expression visit(SizeofExpression e) {
		return makeLiteral(e.location, sizeofCalculator.visit(e.argument));
	}
	
	Expression visit(DeferredExpression e) {
		return handleDeferredExpression!(delegate Expression(Expression e) {
			return visit(e);
		}, Expression)(e);
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
		return this.dispatch!(function Type(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
	}
	
	Type visit(SymbolType t) {
		// TODO: remove when indentifierpass is able to manage this.
		if(auto aliasDecl = cast(AliasDeclaration) t.symbol) {
			return visit(aliasDecl.type);
		}
		
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
		return pass.visit(t.expression).type;
	}
	
	Type visit(PointerType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(SliceType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(StaticArrayType t) {
		t.type = visit(t.type);
		
		return t;
	}
	
	Type visit(FunctionType t) {
		t.returnType = visit(t.returnType);
		
		return t;
	}
}

class DefaultInitializerVisitor {
	private TypecheckPass pass;
	alias pass this;
	
	private Location location;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	Expression visit(Location targetLocation, Type t) {
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = targetLocation;
		
		return this.dispatch!(function Expression(Type t) {
			assert(0, "Type " ~ typeid(t).toString() ~ " has no initializer.");
		})(t);
	}
	
	Expression visit(BooleanType t) {
		return makeLiteral(location, false);
	}
	
	Expression visit(IntegerType t) {
		if(t.type % 2) {
			return new IntegerLiteral!true(location, 0, t);
		} else {
			return new IntegerLiteral!false(location, 0, t);
		}
	}
	
	Expression visit(FloatType t) {
		return new FloatLiteral(location, float.nan, t);
	}
	
	Expression visit(CharacterType t) {
		return new CharacterLiteral(location, [char.init], t);
	}
	
	Expression visit(PointerType t) {
		return new NullLiteral(location, t);
	}
	
	Expression visit(FunctionType t) {
		return new NullLiteral(location, t);
	}
	
	Expression visit(StaticArrayType t) {
		return new VoidInitializer(location, t);
	}
	
	Expression visit(SymbolType t) {
		return this.dispatch(t.symbol);
	}
	
	Expression visit(StructDefinition d) {
		auto fields = cast(FieldDeclaration[]) d.members.filter!(m => typeid(m) is typeid(FieldDeclaration)).array();
		
		return new TupleExpression(location, fields.map!(f => f.value).array());
	}
}

class SizeofCalculator {
	private TypecheckPass pass;
	alias pass this;
	
	this(TypecheckPass pass) {
		this.pass = pass;
	}
	
final:
	uint visit(Type t) {
		return this.dispatch!(function uint(Type t) {
			assert(0, "size of type " ~ typeid(t).toString() ~ " is unknown.");
		})(t);
	}
	
	uint visit(BooleanType t) {
		return 1;
	}
	
	uint visit(IntegerType t) {
		final switch(t.type) {
			case Integer.Byte, Integer.Ubyte :
				return 1;
			
			case Integer.Short, Integer.Ushort :
				return 2;
			
			case Integer.Int, Integer.Uint :
				return 4;
			
			case Integer.Long, Integer.Ulong :
				return 8;
		}
	}
	
	uint visit(FloatType t) {
		final switch(t.type) {
			case Float.Float :
				return 4;
			
			case Float.Double :
				return 8;
			
			case Float.Real :
				return 10;
		}
	}
	
	uint visit(SymbolType t) {
		return visit(t.symbol);
	}
	
	uint visit(TypeSymbol s) {
		return this.dispatch!(function uint(TypeSymbol s) {
			assert(0, "size of type designed by " ~ typeid(s).toString() ~ " is unknown.");
		})(s);
	}
	
	uint visit(AliasDeclaration a) {
		return visit(a.type);
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
			// TODO: remove first if. Equal type should reach here.
			if(t.type == fromType) {
				return e;
			} else if(t.type >> 1 == fromType >> 1) {
				// Same type except for signess.
				return new BitCastExpression(location, type, e);
			} else if(t.type > fromType) {
				return new PadExpression(location, type, e);
			} else static if(isExplicit) {
				return new TruncateExpression(location, type, e);
			} else {
				import std.conv;
				auto msg = "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed";
				
				import sdc.terminal;
				outputCaretDiagnostics(e.location, msg);
				
				assert(0, msg);
			}
		}
	}
	
	final class CastFromFloatType {
		Float fromType;
		
		this(Float fromType) {
			this.fromType = fromType;
		}
		
		Expression visit(Type t) {
			return this.dispatch(t);
		}
		
		Expression visit(FloatType t) {
			import std.conv;
			assert(0, "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed");
		}
	}
	
	final class CastFromCharacterType {
		Character fromType;
		
		this(Character fromType) {
			this.fromType = fromType;
		}
		
		Expression visit(Type t) {
			return this.dispatch(t);
		}
		
		Expression visit(CharacterType t) {
			import std.conv;
			assert(0, "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed");
		}
		
		Expression visit(IntegerType t) {
			Integer i;
			final switch(fromType) {
				case Character.Char :
					i = Integer.Ubyte;
					break;
				
				case Character.Wchar :
					i = Integer.Ushort;
					break;
				
				case Character.Dchar :
					i = Integer.Uint;
					break;
			}
			
			return (new CastFromIntegerType(i)).visit(t);
		}
	}
	
	final class CastFromPointerTo {
		Type fromType;
		
		this(Type fromType) {
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
		
		Expression visit(PointerType t) {
			static if(isExplicit) {
				return new BitCastExpression(location, type, e);
			} else if(auto toType = cast(VoidType) t.type) {
				return new BitCastExpression(location, type, e);
			} else {
				assert(0, "invalid pointer cast.");
			}
		}
		
		static if(isExplicit) {
			Expression visit(FunctionType t) {
				return new BitCastExpression(location, type, e);
			}
		}
	}
	
	
	final class CastFromFunctionTo {
		FunctionType fromType;
		
		this(FunctionType fromType) {
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
		
		Expression visit(PointerType t) {
			static if(isExplicit) {
				return new BitCastExpression(location, type, e);
			} else if(auto toType = cast(VoidType) t.type) {
				return new BitCastExpression(location, type, e);
			} else {
				assert(0, "invalid pointer cast.");
			}
		}
	}
	
	final class Cast {
		Expression visit(Expression e) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(e.type);
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
		
		Expression visit(PointerType t) {
			return (new CastFromPointerTo(t.type)).visit(type);
		}
		
		Expression visit(FunctionType t) {
			return (new CastFromFunctionTo(t)).visit(type);
		}
	}
	
	// Default initializer removal.
	if(typeid(e) is typeid(DefaultInitializer)) {
		return (new DefaultInitializerVisitor(null)).visit(e.location, type);
	}
	
	return (e.type == type)?e:(new Cast()).visit(e);
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
		
		Type visit(CharacterType t) {
			// Should check for RHS. But will fail on implicit cast if LHS isn't the right type for now.
			return t;
		}
		
		Type visit(PointerType t) {
			// FIXME: peform the right pointer promotion.
			return t;
		}
	}
	
	return (new T1Handler()).visit(t1);
}

