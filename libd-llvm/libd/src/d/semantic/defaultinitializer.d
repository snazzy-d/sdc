module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.location;

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
				return new CharacterLiteral(location, [char.init], t);
			
			case Ubyte, Ushort, Uint, Ulong, Ucent :
				return new IntegerLiteral!false(location, 0, t);
			
			case Byte, Short, Int, Long, Cent :
				return new IntegerLiteral!true(location, 0, t);
			
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
			new NullLiteral(location, t),
			new IntegerLiteral!false(location, 0UL, pass.object.getSizeT().type.builtin)
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
		import d.context;
		auto v = new Variable(value.location, value.type, BuiltinName!"", value);
		v.step = Step.Processed;
		
		return new VariableExpression(value.location, v);
	}
	
	E visit(Struct s) {
		scheduler.require(s, Step.Populated);
		
		import d.context;
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
			auto fields = c.members.map!(m => cast(Field) m).filter!(f => !!f).map!(f => f.value).array();
			
			fields[0] = new VtblExpression(location, c);
			if (c.hasContext) {
				import d.context;
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
		auto e = visit(a.type);
		e.type = Type.get(a);
		
		return e;
	}
	
	E visit(Interface i) {
		assert(0, "Not implemented");
	}
	
	E visit(Union u) {
		assert(0, "Not implemented");
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
}

