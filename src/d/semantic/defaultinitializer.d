module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.constant;
import d.ir.error;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;

alias InstanceBuilder = DefaultInitializerVisitor!false;
alias NewBuilder = DefaultInitializerVisitor!true;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct InitBuilder {
	private SemanticPass pass;
	alias pass this;

	Location location;

	this(SemanticPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}

	ConstantExpression asExpression(T)(T t) {
		auto c = new ConstantExpression(location, visit(t));
		static if (is(T : Type)) {
			c.type = c.type.qualify(t.qualifier);
		}

		return c;
	}

	Constant visit(Type t) {
		return t.accept(this);
	}

	Constant visit(BuiltinType t) {
		final switch (t) with (BuiltinType) {
			case None, Void:
				import std.format;
				return new CompileError(
					location,
					format!"%s has no default initializer."(
						Type.get(t).toString(context))
				).constant;

			case Bool:
				return new BooleanConstant(false);

			case Char, Wchar, Dchar:
				return new CharacterConstant(getCharInit(t), t);

			case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent,
			     Ucent:
				return new IntegerConstant(0, t);

			case Float, Double, Real:
				return new FloatConstant(double.nan, t);

			case Null:
				return new NullConstant();
		}
	}

	Constant visitPointerOf(Type t) {
		return new NullConstant(t.getPointer());
	}

	Constant visitSliceOf(Type t) {
		auto sizet = pass.object.getSizeT().type.builtin;
		Constant[] init =
			[new NullConstant(t.getPointer()), new IntegerConstant(0, sizet)];

		return new SplatConstant(t.getSlice(), init);
	}

	Constant visitArrayOf(uint size, Type t) {
		Constant[] elements;
		elements.length = size;
		elements[] = visit(t);

		return new ArrayConstant(t, elements);
	}

	Constant visit(Struct s) {
		if (s.init) {
			return s.init;
		}

		scheduler.require(s, Step.Populated);

		auto fields = s.fields;
		Constant[] elements;
		elements.reserve(fields.length);

		foreach (f; fields) {
			scheduler.require(f);
			elements ~= f.value;
		}

		return s.init = new AggregateConstant(s, elements);
	}

	Constant visit(Union u) {
		scheduler.require(u, Step.Populated);

		Constant value;
		if (u.fields.length > 0) {
			auto f = u.fields[0];
			scheduler.require(f, Step.Signed);

			// FIXME: If the field has an initializer, we should use that.
			value = visit(f.type);
		}

		return new UnionConstant(u, value);
	}

	Constant visit(Class c) {
		return new NullConstant(Type.get(c));
	}

	Constant visit(Interface i) {
		Constant[] init =
			[new NullConstant(Type.get(pass.object.getObject())),
			 new NullConstant(Type.get(BuiltinType.Void).getPointer())];

		return new AggregateConstant(i, init);
	}

	Constant visit(Enum e) {
		assert(0, "Not implemented.");
	}

	Constant visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}

	Constant visit(Function f) {
		assert(0, "Not implemented.");
	}

	Constant visit(Type[] splat) {
		import std.algorithm, std.array;
		auto elements = splat.map!(t => visit(t)).array();

		return new SplatConstant(Type.get(splat), elements);
	}

	Constant visit(ParamType t) {
		assert(!t.isRef, "ref initializer is not implemented.");

		return visit(t.getType());
	}

	Constant visit(FunctionType f) {
		if (f.contexts.length == 0) {
			return new NullConstant(f.getType());
		}

		assert(f.contexts.length == 1,
		       "delegate initializer is not implemented.");

		auto elements = [visit(f.contexts[0]), visit(f.getFunction())];
		return new SplatConstant(f.getType(), elements);
	}

	Constant visit(Pattern p) {
		assert(0, "Patterns have no initializer.");
	}

	Constant visit(CompileError e) {
		return e.constant;
	}
}

private:
struct DefaultInitializerVisitor(bool isNew) {
	private SemanticPass pass;
	alias pass this;

	Location location;

	this(SemanticPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}

	Expression visit(Type t) {
		auto e = t.accept(this);
		e.type = e.type.qualify(t.qualifier);

		return e;
	}

	Expression getDefaultInit(T)(T t) {
		return InitBuilder(pass, location).asExpression(t);
	}

	Expression visit(BuiltinType t) {
		return getDefaultInit(t);
	}

	Expression visitPointerOf(Type t) {
		return getDefaultInit(t);
	}

	Expression visitSliceOf(Type t) {
		return getDefaultInit(t);
	}

	Expression visitArrayOf(uint size, Type t) {
		Expression[] elements;
		elements.length = size;
		elements[] = visit(t);

		return build!TupleExpression(location, t.getArray(size), elements);
	}

	private Expression getTemporary(Expression value) {
		if (auto e = cast(ErrorExpression) value) {
			return e;
		}

		auto loc = value.location;

		import source.name;
		auto v = new Variable(loc, value.type, BuiltinName!"", value);
		v.step = Step.Processed;

		return new VariableExpression(loc, v);
	}

	Expression visit(Struct s) {
		auto v = getDefaultInit(s);
		if (!s.hasContext) {
			return v;
		}

		v = getTemporary(v);

		auto ctxField = s.fields[0];

		import source.name;
		assert(ctxField.name == BuiltinName!"__ctx",
		       "Expected context as first field!");

		auto ctxType = ctxField.type;
		assert(ctxType.kind == TypeKind.Pointer);

		auto ctx = new ContextExpression(location, ctxType.element.context);
		auto assign = new BinaryExpression(
			location,
			ctxType,
			BinaryOp.Assign,
			new FieldExpression(location, v, ctxField),
			new UnaryExpression(location, ctxType, UnaryOp.AddressOf, ctx)
		);

		return new BinaryExpression(location, Type.get(s), BinaryOp.Comma,
		                            assign, v);
	}

	Expression visit(Union u) {
		// FIXME: Computing this properly would require layout
		// informations from the backend. Will do for now.
		return new ConstantExpression(location, new VoidConstant(Type.get(u)));
	}

	Expression visit(Class c) {
		if (!isNew) {
			return getDefaultInit(c);
		}

		scheduler.require(c);

		import std.algorithm, std.array;
		Expression[] fields = c.fields.map!(delegate Expression(Field f) {
			return new ConstantExpression(f.location, f.value);
		}).array();

		fields[0] = new ConstantExpression(
			location,
			new TypeidConstant(Type.get(pass.object.getTypeInfo()), Type.get(c))
		);

		if (c.hasContext) {
			import std.algorithm;
			import source.name;
			auto ctxr = c.fields.filter!(f => f.name == BuiltinName!"__ctx");

			foreach (f; ctxr) {
				auto ft = f.type;
				assert(ft.kind == TypeKind.Pointer);

				fields[f.index] = new UnaryExpression(
					location, ft, UnaryOp.AddressOf,
					new ContextExpression(location, ft.element.context));
			}
		}

		return build!TupleExpression(
			location, Type.get(fields.map!(f => f.type).array()), fields);
	}

	Expression visit(Interface i) {
		return getDefaultInit(i);
	}

	Expression visit(Enum e) {
		return getDefaultInit(e);
	}

	Expression visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}

	Expression visit(Function f) {
		return getDefaultInit(f);
	}

	Expression visit(Type[] splat) {
		import std.algorithm, std.array;
		auto elements = splat.map!(t => visit(t)).array();

		return build!TupleExpression(location, Type.get(splat), elements);
	}

	Expression visit(ParamType t) {
		assert(!t.isRef, "ref initializer is not implemented.");

		return visit(t.getType());
	}

	Expression visit(FunctionType f) {
		if (f.contexts.length == 0) {
			return getDefaultInit(f);
		}

		assert(f.contexts.length == 1,
		       "delegate initializer is not implemented.");

		auto elements = [visit(f.contexts[0]), visit(f.getFunction())];
		return build!TupleExpression(location, f.getType(), elements);
	}

	Expression visit(Pattern p) {
		return getDefaultInit(p);
	}

	Expression visit(CompileError e) {
		return getDefaultInit(e);
	}
}
