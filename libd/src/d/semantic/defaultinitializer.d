module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.context.location;

alias InitBuilder = DefaultInitializerVisitor!(true, false);
alias InstanceBuilder = DefaultInitializerVisitor!(false, false);
alias NewBuilder = DefaultInitializerVisitor!(false, true);

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

private:
struct DefaultInitializerVisitor(bool isCompileTime, bool isNew) {
	static assert(!isCompileTime || !isNew);
	
	static if(isCompileTime) {
		alias E = CompileTimeExpression;
	} else {
		alias E = Expression;
	}
	
	private SemanticPass pass;
	alias pass this;
	
	Location location;
	
	this(SemanticPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}
	
	E visit(Type t) {
		auto e = t.accept(this);
		e.type = e.type.qualify(t.qualifier);
		
		return e;
	}
	
	E visit(BuiltinType t) {
		final switch(t) with(BuiltinType) {
			case None :
			case Void :
				import d.exception;
				throw new CompileException(location, Type.get(t).toString(context));
			
			case Bool :
				return new BooleanLiteral(location, false);
			
			case Char, Wchar, Dchar :
				return new CharacterLiteral(location, getCharInit(t), t);
			
			case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent, Ucent :
				return new IntegerLiteral(location, 0, t);
			
			case Float, Double, Real :
				return new FloatLiteral(location, float.nan, t);
			
			case Null :
				return new NullLiteral(location);
		}
	}
	
	E visitPointerOf(Type t) {
		return new NullLiteral(location, t.getPointer());
	}
	
	E visitSliceOf(Type t) {
		CompileTimeExpression[] init = [
			new NullLiteral(location, t.getPointer()),
			new IntegerLiteral(location, 0UL, pass.object.getSizeT().type.builtin)
		];
		
		// XXX: Should cast to size_t, but buildImplicitCast doesn't produce CompileTimeExpressions.
		return new CompileTimeTupleExpression(location, t.getSlice(), init);
	}
	
	E visitArrayOf(uint size, Type t) {
		E[] elements;
		elements.length = size;
		elements[] = visit(t);
		
		static if (isCompileTime) {
			return new CompileTimeTupleExpression(location, t.getArray(size), elements);
		} else {
			return new TupleExpression(location, t.getArray(size), elements);
		}
	}
	
	private Expression getTemporary(Expression value) {
		import d.context.name;
		auto v = new Variable(value.location, value.type, BuiltinName!"", value);
		v.step = Step.Processed;
		
		return new VariableExpression(value.location, v);
	}
	
	E visit(Struct s) {
		scheduler.require(s, Step.Signed);
		
		import d.context.name;
		auto init = cast(Variable) s.dscope.resolve(BuiltinName!"init");
		assert(init, "init must be defined");
		
		scheduler.require(init);
		
		static if(isCompileTime) {
			auto v = cast(E) init.value;
			assert(v, "init must be a compile time expression");
			
			return v;
		} else {
			auto v = init.value;
			if (!s.hasContext) {
				return v;
			}
			
			v = getTemporary(v);
			
			import std.algorithm;
			auto f = cast(Field) s.members.filter!(m => m.name == BuiltinName!"__ctx").front;
			assert(f, "Context must be a field");
			
			auto ft = f.type;
			assert(ft.kind == TypeKind.Pointer);
			
			auto assign = new BinaryExpression(
				location,
				ft,
				BinaryOp.Assign,
				new FieldExpression(location, v, f),
				new UnaryExpression(location, ft, UnaryOp.AddressOf, new ContextExpression(location, ft.element.context)),
			);
			
			return new BinaryExpression(location, Type.get(s), BinaryOp.Comma, assign, v);
		}
	}
	
	E visit(Class c) {
		static if(isNew) {
			scheduler.require(c);
			
			import std.algorithm, std.array;
			auto fields = c.members
				.map!(m => cast(Field) m)
				.filter!(f => !!f)
				.map!(function Expression(f) { return f.value; })
				.array();
			
			fields[0] = new VtblExpression(location, c);
			if (c.hasContext) {
				import d.context.name;
				import std.algorithm;
				foreach(f; c.members.filter!(m => m.name == BuiltinName!"__ctx").map!(m => cast(Field) m)) {
					assert(f, "Context must be a field");
					
					auto ft = f.type;
					assert(ft.kind == TypeKind.Pointer);
					
					fields[f.index] = new UnaryExpression(location, ft, UnaryOp.AddressOf, new ContextExpression(location, ft.element.context));
				}
			}
			
			return new TupleExpression(location, Type.get(fields.map!(f => f.type).array()), fields);
		} else {
			return new NullLiteral(location, Type.get(c));
		}
	}
	
	E visit(Enum e) {
		assert(0, "Not implemented");
	}
	
	E visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}
	
	E visit(Interface i) {
		CompileTimeExpression[] init = [
			new NullLiteral(location, Type.get(pass.object.getObject())), // object
			new NullLiteral(location, Type.get(BuiltinType.Void).getPointer()) // vtable
		];
		return new CompileTimeTupleExpression(location, Type.get(i), init);
	}
	
	E visit(Union u) {
		// FIXME: Computing this properly would require layout
		// informations from the backend. Will do for now.
		return new VoidInitializer(location, Type.get(u));
	}
	
	E visit(Function f) {
		assert(0, "Not implemented");
	}
	
	E visit(Type[] seq) {
		import std.algorithm, std.array;
		auto elements = seq.map!(t => visit(t)).array();
		
		static if (isCompileTime) {
			return new CompileTimeTupleExpression(location, Type.get(seq), elements);
		} else {
			return new TupleExpression(location, Type.get(seq), elements);
		}
	}
	
	E visit(FunctionType f) {
		assert(f.contexts.length == 0, "delegate initializer is not implemented.");
		return new NullLiteral(location, f.getType());
	}
	
	E visit(TypeTemplateParameter p) {
		assert(0, "Template type have no initializer.");
	}
	
	import d.ir.error;
	E visit(CompileError e) {
		return e.expression;
	}
}

