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
	
	private Cast!false implicitCast;
	private Cast!true explicitCast;
	
	private Type returnType;
	private Type thisType;
	
	private Type[Symbol] resolvedTypes;
	private bool runAgain;
	
	this() {
		declarationVisitor	= new DeclarationVisitor(this);
		statementVisitor	= new StatementVisitor(this);
		expressionVisitor	= new ExpressionVisitor(this);
		typeVisitor			= new TypeVisitor(this);
		
		defaultInitializerVisitor = new DefaultInitializerVisitor(this);
		
		sizeofCalculator	= new SizeofCalculator(this);
		
		implicitCast		= new Cast!false(this);
		explicitCast		= new Cast!true(this);
	}
	
final:
	Module[] visit(Module[] modules) {
		import d.pass.identifier;
		auto identifierPass = new IdentifierPass();
		
		modules = identifierPass.visit(modules);
		
		// Set reference to null to allow garbage collection.
		identifierPass = null;
		
		auto oldRunAgain = runAgain;
		scope(exit) runAgain = oldRunAgain;
		
		runAgain = true;
		auto resolvedCount = resolvedTypes.length;
		
		uint count;
		while(runAgain) {
			version(GC_CRASH) {
				import core.memory;
				GC.collect();
			}
			
			import std.stdio;
			writeln("typecheck count: ", count++);
			
			runAgain = false;
			modules = modules.map!(m => visit(m)).array();
			
			// TODO: ensure that this is making progress.
			resolvedCount = resolvedTypes.length;
		}
		
		return modules;
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
	Declaration visit(Declaration d) out(result) {
		assert(result);
		
		if(auto asSym = cast(Symbol) result) {
			assert(pass.runAgain || (asSym in pass.resolvedTypes));
		}
	} body {
		return this.dispatch(d);
	}
	
	Symbol visit(FunctionDeclaration d) {
		auto ret = pass.visit(d.returnType);
		
		if(!ret) return d;
		
		d.returnType = ret;
		
		resolvedTypes[d] = d.type = new FunctionType(d.location, d.linkage, d.returnType, d.parameters, d.isVariadic);
		
		return d;
	}
	
	Symbol visit(FunctionDefinition d) {
		// XXX: need array in the middle to avoid double evaluation of map.
		auto parameters = d.parameters.map!(p => this.dispatch(p)).array.filter!(p => !!(p in pass.resolvedTypes)).array();
		
		if(parameters.length != d.parameters.length) return d;
		
		d.parameters = parameters;
		
		if(typeid({ return d.returnType; }()) !is typeid(AutoType)) {
			auto ret = pass.visit(d.returnType);
			
			if(!ret) return d;
			
			d.returnType = ret;
		}
		
		// Prepare statement visitor for return type.
		auto oldReturnType = returnType;
		scope(exit) returnType = oldReturnType;
		
		returnType = d.returnType;
		
		// TODO: move that into an ADT pass.
		// If it isn't a static method, add this.
		// checking resolvedTypes Ensure that it isn't ran twice.
		if(!d.isStatic && !(d in resolvedTypes)) {
			auto thisParameter = new Parameter(d.location, "this", thisType);
			thisParameter.isReference = true;
			
			d.parameters = thisParameter ~ d.parameters;
		}
		
		// And visit.
		pass.visit(d.fbody);
		
		if(typeid({ return d.returnType; }()) is typeid(AutoType)) {
			// Should be useless once return type inference is properly implemented.
			if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
				assert(runAgain);
				
				return d;
			}
			
			d.returnType = returnType;
		}
		
		resolvedTypes[d] = d.type = new FunctionType(d.location, d.linkage, d.returnType, d.parameters, d.isVariadic);
		
		return d;
	}
	
	VariableDeclaration visit(VariableDeclaration var) {
		var.value = pass.visit(var.value);
		
		Type type;
		
		// If the type is infered, then we use the type of the value.
		if(typeid({ return var.type; }()) is typeid(AutoType)) {
			if(var.value.type) {
				type = var.value.type;
			}
		} else {
			type = pass.visit(var.type);
		}
		
		if(type) {
			var.value = implicitCast.build(var.location, type, var.value);
			
			resolvedTypes[var] = var.type = type;
		} else {
			assert(runAgain);
		}
		
		return var;
	}
	
	Symbol visit(FieldDeclaration f) {
		return visit(cast(VariableDeclaration) f);
	}
	
	Symbol visit(StructDefinition d) {
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(d.location, d);
		
		auto initDecl = cast(VariableDeclaration) d.dscope.resolve("init");
		assert(initDecl);
		if(!(initDecl in resolvedTypes)) {
			auto fields = cast(FieldDeclaration[]) d.members.filter!(m => typeid(m) is typeid(FieldDeclaration)).array.map!(f => visit(f)).array();
			
			if(fields.filter!(f => !!(f in pass.resolvedTypes)).count() == fields.length) {
				auto tuple = new TupleExpression(d.location, fields.map!(f => f.value).array());
				
				tuple.type = thisType;
				
				initDecl.value = tuple;
				initDecl.type = thisType;
				
				resolvedTypes[initDecl] = thisType;
			}
		}
		
		resolvedTypes[d] = thisType;
		d.members = d.members.filter!(delegate bool(Declaration m) { return m !is initDecl; }).map!(m => visit(m)).array() ~ initDecl;
		
		// Check if everything went well.
		if(d.members.filter!((m) {
			if(auto asSym = cast(Symbol) m) {
				return !!(asSym in pass.resolvedTypes);
			}
			
			assert(0, "struct should contains only symbols at this point.");
		}).count() != d.members.length) {
			assert(runAgain);
			
			resolvedTypes.remove(d);
		}
		
		return d;
	}
	
	Symbol visit(ClassDefinition d) {
		auto oldThisType = thisType;
		scope(exit) thisType = oldThisType;
		
		thisType = new SymbolType(d.location, d);
		
		d.members = d.members.map!(m => visit(m)).array();
		
		resolvedTypes[d] = thisType;
		
		return d;
	}
	
	Symbol visit(EnumDeclaration d) {
		if(d in resolvedTypes) {
			return d;
		}
		
		auto type = pass.visit(d.type);
		
		if(type) {
			if(auto asEnum = cast(EnumType) type) {
				if(typeid({ return asEnum.type; }()) !is typeid(IntegerType)) {
					assert(0, "enum are of integer type.");
				}
			} else {
				assert(0, "enum must have an enum type !");
			}
			
			VariableDeclaration previous;
			uint value;
			foreach(e; d.enumEntries) {
				// FIXME: temporary hack when waiting for CTFE.
				e.value = makeLiteral(e.location, value++);
				
				if(typeid({ return e.value; }()) is typeid(DefaultInitializer)) {
					if(previous) {
						e.value = new AddExpression(e.location, new SymbolExpression(e.location, previous), makeLiteral(e.location, 1));
					} else {
						e.value = makeLiteral(e.location, 0);
					}
				}
				
				e.value = explicitCast.build(e.location, type, pass.visit(e.value));
				
				resolvedTypes[e] = e.type = type;
				
				previous = e;
			}
			
			resolvedTypes[d] = d.type = type;
		}
		
		return d;
	}
	
	Parameter visit(Parameter p) {
		auto type = pass.visit(p.type);
		
		if(type) {
			resolvedTypes[p] = p.type = pass.visit(p.type);
		}
		
		return p;
	}
	
	Symbol visit(AliasDeclaration d) {
		auto type = pass.visit(d.type);
		
		if(type) {
			resolvedTypes[d] = d.type = type;
		}
		
		return d;
	}
	
	Symbol visit(TemplateDeclaration tpl) {
		foreach(instance; tpl.instances) {
			instance.declarations = instance.declarations.map!(d => visit(d)).array();
		}
		
		// Template have no type.
		resolvedTypes[tpl] = null;
		
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
	
	void visit(LabeledStatement s) {
		visit(s.statement);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfElseStatement ifs) {
		ifs.condition = explicitCast.build(ifs.condition.location, new BooleanType(ifs.condition.location), pass.visit(ifs.condition));
		
		visit(ifs.then);
		visit(ifs.elseStatement);
	}
	
	void visit(WhileStatement w) {
		w.condition = explicitCast.build(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(DoWhileStatement w) {
		w.condition = explicitCast.build(w.condition.location, new BooleanType(w.condition.location), pass.visit(w.condition));
		
		visit(w.statement);
	}
	
	void visit(ForStatement f) {
		visit(f.initialize);
		
		f.condition = explicitCast.build(f.condition.location, new BooleanType(f.condition.location), pass.visit(f.condition));
		f.increment = pass.visit(f.increment);
		
		visit(f.statement);
	}
	
	void visit(ReturnStatement r) {
		r.value = pass.visit(r.value);
		
		if(!r.value.type) return;
		
		// TODO: precompute autotype instead of managing it here.
		if(typeid({ return pass.returnType; }()) is typeid(AutoType)) {
			returnType = r.value.type;
		} else {
			r.value = implicitCast.build(r.location, returnType, r.value);
		}
	}
	
	void visit(BreakStatement s) {
		// Nothing needs to be done.
	}
	
	void visit(ContinueStatement s) {
		// Nothing needs to be done.
	}
	
	void visit(GotoStatement s) {
		// Nothing needs to be done.
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
		if(!pass.runAgain) {
			if(!result.type) {
				if(!cast(PolysemousExpression) result) {
					auto msg = "Type should have been set for expression " ~ typeid(result).toString() ~ " at this point.";
					
					import sdc.terminal;
					outputCaretDiagnostics(result.location, msg);
					
					assert(0, msg);
				}
			}
			
			assert(!(cast(AutoType) result.type));
		}
	} body {
		return this.dispatch(e);
	}
	
	Expression visit(PolysemousExpression e) {
		e.expressions = e.expressions.map!(e => visit(e)).array();
		
		return e;
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
		
		e.rhs = implicitCast.build(e.rhs.location, e.type, visit(e.rhs));
		
		return e;
	}
	
	private Expression handleArithmeticExpression(string operation)(BinaryExpression!operation e) if(find(["+", "+=", "-", "-="], operation)) {
		enum isOpAssign = operation.length == 2;
		
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		// This will be processed at the next pass.
		if(!(e.lhs.type && e.rhs.type)) return e;
		
		if(auto pointerType = cast(PointerType) e.lhs.type) {
			if(typeid({ return e.rhs.type; }()) !is typeid(IntegerType)) {
				return compilationCondition!Expression(e.rhs.location, "Pointer +/- interger only.");
			}
			
			// FIXME: introduce temporary.
			static if(operation[0] == '+') {
				auto value = new AddressOfExpression(e.location, new IndexExpression(e.location, e.lhs, [e.rhs]));
			} else {
				auto value = new AddressOfExpression(e.location, new IndexExpression(e.location, e.lhs, [visit(new UnaryMinusExpression(e.location, e.rhs))]));
			}
			
			static if(isOpAssign) {
				auto ret = new AssignExpression(e.location, e.lhs, value);
			} else {
				alias value ret;
			}
			
			return visit(ret);
		}
		
		static if(isOpAssign) {
			e.type = e.lhs.type;
		} else {
			e.type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = implicitCast.build(e.lhs.location, e.type, e.lhs);
		}
		
		e.rhs = implicitCast.build(e.rhs.location, e.type, e.rhs);
		
		return e;
	}
	
	Expression visit(AddExpression e) {
		return handleArithmeticExpression(e);
	}
	
	Expression visit(SubExpression e) {
		return handleArithmeticExpression(e);
	}
	
	Expression visit(AddAssignExpression e) {
		return handleArithmeticExpression(e);
	}
	
	Expression visit(SubAssignExpression e) {
		return handleArithmeticExpression(e);
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		import std.algorithm;
		static if(find(["&&", "||"], operation)) {
			e.type = new BooleanType(e.location);
			
			e.lhs = explicitCast.build(e.lhs.location, e.type, e.lhs);
			e.rhs = explicitCast.build(e.rhs.location, e.type, e.rhs);
		} else static if(find(["==", "!=", ">", ">=", "<", "<="], operation)) {
			auto type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = implicitCast.build(e.lhs.location, type, e.lhs);
			e.rhs = implicitCast.build(e.rhs.location, type, e.rhs);
			
			e.type = new BooleanType(e.location);
		} else static if(find(["&", "|", "^", "*", "/", "%"], operation)) {
			e.type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = implicitCast.build(e.lhs.location, e.type, e.lhs);
			e.rhs = implicitCast.build(e.rhs.location, e.type, e.rhs);
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
		
		return compilationCondition!Expression(e.location, "Increment and decrement are performed on integers or pointer types.");
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
	
	Expression visit(UnaryMinusExpression e) {
		e.expression = visit(e.expression);
		e.type = e.expression.type;
		
		return e;
	}
	
	Expression visit(UnaryPlusExpression e) {
		auto expression = visit(e.expression);
		
		if(expression.type) {
			if(typeid({ return expression.type; }()) !is typeid(IntegerType)) {
				return compilationCondition!Expression(e.location, "unary plus only apply to integers.");
			}
			
			return expression;
		}
		
		e.expression = expression;
		return e;
	}
	
	Expression visit(NotExpression e) {
		e.type = new BooleanType(e.location);
		e.expression = explicitCast.build(e.location, e.type, visit(e.expression));
		
		return e;
	}
	
	Expression visit(AddressOfExpression e) {
		if(typeid({ return e.expression; }()) is typeid(AddressOfExpression)) {
			return compilationCondition!Expression(e.location, "Cannot take the address of an address.");
		}
		
		e.expression = visit(e.expression);
		
		// For fucked up reasons, &funcname is a special case.
		if(auto asSym = cast(SymbolExpression) e.expression) {
			if(auto asDecl = cast(FunctionDeclaration) asSym.symbol) {
				return e.expression;
			}
		}
		
		if(e.expression.type) {
			e.type = new PointerType(e.location, e.expression.type);
		} else {
			e.type = null;
		}
		
		return e;
	}
	
	Expression visit(DereferenceExpression e) {
		e.expression = visit(e.expression);
		
		// TODO: handle function dereference.
		if(auto pt = cast(PointerType) e.expression.type) {
			e.type = pt.type;
			
			return e;
		}
		
		return compilationCondition!Expression(e.location, typeid({ return e.expression.type; }()).toString() ~ " is not a pointer type.");
	}
	
	Expression visit(CastExpression e) {
		return explicitCast.build(e.location, pass.visit(e.type), visit(e.expression));
	}
	
	Expression visit(BitCastExpression e) {
		// XXX: Should something be done here ?
		return e;
	}
	
	Expression visit(CallExpression c) {
		c.callee = visit(c.callee);
		
		if(auto asPolysemous = cast(PolysemousExpression) c.callee) {
			auto candidates = asPolysemous.expressions.filter!(delegate bool(Expression e) {
				e = visit(e);
				
				if(e.type is null) {
					return true;
				}
				
				if(auto asFunType = cast(FunctionType) e.type) {
					if(asFunType.isVariadic) {
						return c.arguments.length >= asFunType.parameters.length;
					} else {
						return c.arguments.length == asFunType.parameters.length;
					}
				}
				
				// We only reach that point if some types needs more processing.
				assert(pass.runAgain);
				return true;
			}).array();
			
			if(candidates.length == 1) {
				c.callee = candidates[0];
			} else if(candidates.length > 1) {
				if(runAgain) {
					// Remove excluded candidates if apropriate.
					if(asPolysemous.expressions.length > candidates.length) {
						c.callee = new PolysemousExpression(asPolysemous.location, candidates);
					}
					
					c.type = null;
					
					return c;
				}
				
				return compilationCondition!Expression(c.location, "ambigusous function call.");
			} else {
				// No candidate.
				return compilationCondition!Expression(c.location, "No candidate for function call.");
			}
		}
		
		// XXX: is it the appropriate place to perform that ?
		if(auto me = cast(MethodExpression) c.callee) {
			c.callee = visit(new SymbolExpression(me.location, me.method));
			c.arguments = visit(me.thisExpression) ~ c.arguments;
		}
		
		if(!c.callee.type) {
			c.type = null;
			
			return c;
		}
		
		auto type = cast(FunctionType) c.callee.type;
		if(!type) {
			return compilationCondition!Expression(c.location, "You must call function, you fool !!!");
		}
		
		c.arguments = c.arguments.map!(a => pass.visit(a)).array();
		
		assert(c.arguments.length >= type.parameters.length);
		foreach(ref arg, param; lockstep(c.arguments, type.parameters)) {
			arg = pass.implicitCast.build(arg.location, param.type, arg);
			
			if(!arg.type) {
				c.type = null;
				
				return c;
			}
		}
		
		c.type = type.returnType;
		
		return c;
	}
	
	Expression visit(FieldExpression fe) {
		fe.expression = visit(fe.expression);
		
		fe.type = fe.field.type;
		
		return fe;
	}
	
	Expression visit(MethodExpression me) {
		me.thisExpression = visit(me.thisExpression);
		
		if(auto typePtr = me.method in resolvedTypes) {
			me.type = *typePtr;
		} else {
			runAgain = true;
			me.type = null;
		}
		
		return me;
	}
	
	Expression visit(ThisExpression e) {
		e.type = thisType;
		
		return e;
	}
	
	Expression visit(SymbolExpression e) {
		if(auto typePtr = e.symbol in resolvedTypes) {
			e.type = *typePtr;
		} else {
			runAgain = true;
			e.type = null;
		}
		
		return e;
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
		
		if(!e.type) {
			return compilationCondition!Expression(e.location, "Can't index " ~ typeid({ return e.indexed; }()).toString());
		}
		
		e.arguments = e.arguments.map!(e => visit(e)).array();
		
		return e;
	}
	
	Expression visit(SliceExpression e) {
		// TODO: check if it is valid.
		e.indexed = visit(e.indexed);
		
		if(auto asSlice = cast(SliceType) e.indexed.type) {
			e.type = asSlice.type;
		} else if(auto asPointer = cast(PointerType) e.indexed.type) {
			e.type = asPointer.type;
		} else if(auto asStaticArray = cast(StaticArrayType) e.indexed.type) {
			e.type = asStaticArray.type;
		}
		
		if(!e.type) {
			return compilationCondition!Expression(e.location, "Can't slice " ~ typeid({ return e.indexed; }()).toString());
		}
		
		e.type = new SliceType(e.location, e.type);
		
		e.first = e.first.map!(e => visit(e)).array();
		e.second = e.second.map!(e => visit(e)).array();
		
		return e;
	}
	
	Expression visit(SizeofExpression e) {
		return makeLiteral(e.location, sizeofCalculator.visit(e.argument));
	}
	
	Expression visit(DeferredExpression e) {
		auto ret = handleDeferredExpression!(delegate Expression(Expression e) {
			return visit(e);
		}, Expression)(e);
		
		if(!ret.type) runAgain = true;
		
		return ret;
	}
	
	// Will be remove by cast operation.
	Expression visit(DefaultInitializer di) {
		return di;
	}
	
	Expression visit(AssertExpression e) {
		e.arguments = e.arguments.map!(a => visit(a)).array();
		
		e.arguments[0] = explicitCast.build(e.location, new BooleanType(e.location), e.arguments[0]);
		
		assert(e.arguments.length == 1, "Assert with message isn't supported.");
		
		e.type = new VoidType(e.location);
		
		return e;
	}
	
	Expression visit(TupleExpression e) {
		// FIXME: validate tuple type.
		return e;
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
	Type visit(Type t) out(result) {
		assert(pass.runAgain || result, "A type must be returned.");
	} body {
		return this.dispatch!(function Type(Type t) {
			auto msg = typeid(t).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(t.location, msg);
			
			assert(0, msg);
		})(t);
	}
	
	Type visit(SymbolType t) {
		if(auto typePtr = t.symbol in resolvedTypes) {
			return *typePtr;
		}
		
		runAgain = true;
		
		return null;
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
		
		return t.expression.type;
	}
	
	auto handleSuffixType(T)(T t) {
		auto type = visit(t.type);
		
		if(type) {
			t.type = type;
			
			return t;
		}
		
		return null;
	}
	
	Type visit(PointerType t) {
		return handleSuffixType(t);
	}
	
	Type visit(SliceType t) {
		return handleSuffixType(t);
	}
	
	Type visit(StaticArrayType t) {
		return handleSuffixType(t);
	}
	
	Type visit(EnumType t) {
		return handleSuffixType(t);
	}
	
	Type visit(FunctionType t) {
		auto returnType = visit(t.returnType);
		
		if(returnType) {
			t.returnType = returnType;
			
			return t;
		}
		
		return null;
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
	Expression visit(Location targetLocation, Type t) out(result) {
		if(!(pass.runAgain || result.type)) {
			auto msg = "Type should have been set for default initializer " ~ typeid(result).toString() ~ " at this point.";
			
			import sdc.terminal;
			outputCaretDiagnostics(result.location, msg);
			
			assert(0, msg);
		}
	} body {
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = targetLocation;
		
		return this.dispatch!(delegate Expression(Type t) {
			return compilationCondition!Expression(location, "Type " ~ typeid(t).toString() ~ " has no initializer.");
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
	
	Expression visit(SliceType t) {
		// Convoluted way to create the array due to compiler limitations.
		Expression[] init = [new NullLiteral(location, t.type)];
		init ~= makeLiteral(location, 0UL);
		
		auto ret = new TupleExpression(location, init);
		ret.type = t;
		
		return ret;
	}
	
	Expression visit(StaticArrayType t) {
		return new VoidInitializer(location, t);
	}
	
	Expression visit(SymbolType t) {
		// TODO: add implicit cast
		return this.dispatch(t.symbol);
	}
	
	Expression visit(StructDefinition d) {
		if(d in resolvedTypes) {
			auto init = cast(ExpressionSymbol) d.dscope.resolve("init");
			
			if(init in resolvedTypes) {
				return pass.visit(new SymbolExpression(location, init));
			}
		}
		
		runAgain = true;
		
		return new DefaultInitializer(new SymbolType(location, d));
	}
	
	Expression visit(ClassDefinition d) {
		return new NullLiteral(location, new SymbolType(d.location, d));
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

class Cast(bool isExplicit) {
	private TypecheckPass pass;
	alias pass this;
	
	private Location location;
	private Type type;
	private Expression expression;
	
	private FromBoolean fromBoolean;
	private FromInteger fromInteger;
	private FromCharacter fromCharacter;
	private FromPointer fromPointer;
	private FromFunction fromFunction;
	
	this(TypecheckPass pass) {
		this.pass = pass;
		
		fromBoolean		= new FromBoolean();
		fromInteger		= new FromInteger();
		// fromFloat		= new FromFloat();
		fromCharacter	= new FromCharacter();
		fromPointer		= new FromPointer();
		fromFunction	= new FromFunction();
	}
	
final:
	Expression build(Location castLocation, Type to, Expression e) out(result) {
		assert(pass.runAgain || (result.type == to));
	} body {
		// If the expression is polysemous, we try the several meaning and exclude the ones that make no sense.
		if(auto asPolysemous = cast(PolysemousExpression) e) {
			Expression[] casted;
			foreach(candidate; asPolysemous.expressions) {
				import sdc.compilererror;
				try {
					casted ~= build(castLocation, to, candidate);
				} catch(CompilerError ce) {}
			}
			
			if(casted.length == 1) {
				return casted[0];
			} else if(casted.length > 1 ){
				if(runAgain) {
					if(casted.length < asPolysemous.expressions.length) {
						asPolysemous = new PolysemousExpression(asPolysemous.location, casted);
					}
					
					return asPolysemous;
				}
				
				return compilationCondition!Expression(e.location, "Ambiguous.");
			} else {
				return compilationCondition!Expression(e.location, "No match found.");
			}
		}
		
		if(runAgain) {
			if(!(to && e.type)) return e;
		}
		
		assert(to && e.type);
		
		// Default initializer removal.
		if(typeid(e) is typeid(DefaultInitializer)) {
			return defaultInitializerVisitor.visit(e.location, to);
		}
		
		// Nothing to cast.
		if(e.type == to) return e;
		
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = castLocation;
		
		auto oldType = type;
		scope(exit) type = oldType;
		
		type = to;
		
		auto oldExpression = expression;
		scope(exit) expression = oldExpression;
		
		expression = e;
		
		return this.dispatch!(delegate Expression(Type t) {
			auto msg = typeid(t).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(t.location, msg);
			outputCaretDiagnostics(location, msg);
			
			outputCaretDiagnostics(to.location, "to " ~ typeid(to).toString());
			
			assert(0, msg);
		})(e.type);
	}
	
	class FromBoolean {
		Expression visit(Type t) {
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Expression visit(IntegerType t) {
			return new PadExpression(location, t, expression);
		}
	}
	
	Expression visit(BooleanType t) {
		return fromBoolean.visit(type);
	}
	
	class FromInteger {
		Integer fromType;
		
		Expression visit(Integer from, Type to) {
			auto oldFromType = fromType;
			scope(exit) fromType = oldFromType;
			
			fromType = from;
			
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
		}
		
		static if(isExplicit) {
			Expression visit(BooleanType t) {
				Expression zero = makeLiteral(location, 0);
				auto type = getPromotedType(location, expression.type, zero.type);
				
				zero = pass.implicitCast.build(location, type, zero);
				expression = pass.implicitCast.build(expression.location, type, expression);
				
				auto res = new NotEqualityExpression(location, expression, zero);
				res.type = t;
				
				return res;
			}
			
			Expression visit(EnumType t) {
				// If the cast is explicit, then try to cast from enum base type.
				return new BitCastExpression(location, t, build(location, t.type, expression));
			}
		}
		
		Expression visit(IntegerType t) {
			if(t.type >> 1 == fromType >> 1) {
				// Same type except for signess.
				return new BitCastExpression(location, t, expression);
			} else if(t.type > fromType) {
				return new PadExpression(location, t, expression);
			} else static if(isExplicit) {
				return new TruncateExpression(location, t, expression);
			} else {
				import std.conv;
				return compilationCondition!Expression(expression.location, "Implicit cast from " ~ to!string(fromType) ~ " to " ~ to!string(t.type) ~ " is not allowed");
			}
		}
	}
	
	Expression visit(IntegerType t) {
		return fromInteger.visit(t.type, type);
	}
	
	/*
	Expression visit(FloatType t) {
		return fromFloatType(t.type)).visit(type);
	}
	*/
	
	class FromCharacter {
		Character fromType;
		
		Expression visit(Character from, Type to) {
			auto oldFromType = fromType;
			scope(exit) fromType = oldFromType;
			
			fromType = from;
			
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
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
			
			return fromInteger.visit(i, t);
		}
	}
	
	Expression visit(CharacterType t) {
		return fromCharacter.visit(t.type, type);
	}
	
	class FromPointer {
		Type fromType;
		
		Expression visit(Type from, Type to) {
			auto oldFromType = fromType;
			scope(exit) fromType = oldFromType;
			
			fromType = from;
			
			return this.dispatch!(function Expression(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(to);
		}
		
		Expression visit(PointerType t) {
			static if(isExplicit) {
				return new BitCastExpression(location, t, expression);
			} else if(auto toType = cast(VoidType) t.type) {
				return new BitCastExpression(location, t, expression);
			} else {
				return compilationCondition!Expression(location, "invalid pointer cast.");
			}
		}
		
		static if(isExplicit) {
			Expression visit(FunctionType t) {
				return new BitCastExpression(location, t, expression);
			}
		}
	}
	
	Expression visit(PointerType t) {
		return fromPointer.visit(t.type, type);
	}
	
	class FromFunction {
		FunctionType fromType;
		
		Expression visit(FunctionType from, Type to) {
			auto oldFromType = fromType;
			scope(exit) fromType = oldFromType;
			
			fromType = from;
			
			return this.dispatch!(function Expression(Type t) {
				return compilationCondition!Expression(t.location, typeid(t).toString() ~ " is not supported.");
			})(to);
		}
		
		Expression visit(PointerType t) {
			static if(isExplicit) {
				return new BitCastExpression(location, t, expression);
			} else if(auto toType = cast(VoidType) t.type) {
				return new BitCastExpression(location, t, expression);
			} else {
				return compilationCondition!Expression(location, "invalid pointer cast.");
			}
		}
	}
	
	Expression visit(FunctionType t) {
		return fromFunction.visit(t, type);
	}
	
	Expression visit(EnumType t) {
		// Automagically promote to base type.
		return build(location, type, new BitCastExpression(location, t.type, expression));
	}
}

Type getPromotedType(Location location, Type t1, Type t2) {
	// If an unresolved type come here, the pass wil run again so we just skip.
	if(!(t1 && t2)) return null;
	
	final class T2Handler {
		Integer t1type;
		
		this(Integer t1type) {
			this.t1type = t1type;
		}
		
		Type visit(Type t) {
			return this.dispatch!(function Type(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
		}
		
		Type visit(BooleanType t) {
			return new IntegerType(location, max(t1type, Integer.Int));
		}
		
		Type visit(IntegerType t) {
			// Type smaller than int are promoted to int.
			auto t2type = max(t.type, Integer.Int);
			
			return new IntegerType(location, max(t1type, t2type));
		}
	}
	
	final class T1Handler {
		Type visit(Type t) {
			return this.dispatch!(function Type(Type t) {
				auto msg = typeid(t).toString() ~ " is not supported.";
				
				import sdc.terminal;
				outputCaretDiagnostics(t.location, msg);
				
				assert(0, msg);
			})(t);
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
			// FIXME: check RHS.
			return t;
		}
		
		Type visit(EnumType t) {
			if(auto asInt = cast(IntegerType) t.type) {
				return visit(asInt);
			}
			
			assert(0, "Enum are of type int.");
		}
	}
	
	return (new T1Handler()).visit(t1);
}

