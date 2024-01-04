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

	CompileTimeExpression visit(Type t) {
		auto e = t.accept(this);
		e.type = e.type.qualify(t.qualifier);

		return e;
	}

	CompileTimeExpression visit(BuiltinType t) {
		final switch (t) with (BuiltinType) {
			case None, Void:
				import std.format;
				return new CompileError(
					location,
					format!"%s has no default initializer."(
						Type.get(t).toString(context))
				).expression;

			case Bool:
				return new ConstantExpression(location,
				                              new BooleanConstant(false));

			case Char, Wchar, Dchar:
				return new ConstantExpression(
					location, new CharacterConstant(getCharInit(t), t));

			case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent,
			     Ucent:
				return
					new ConstantExpression(location, new IntegerConstant(0, t));

			case Float, Double, Real:
				return new ConstantExpression(location,
				                              new FloatConstant(double.nan, t));

			case Null:
				return new ConstantExpression(location, new NullConstant());
		}
	}

	CompileTimeExpression visitPointerOf(Type t) {
		return
			new ConstantExpression(location, new NullConstant(t.getPointer()));
	}

	CompileTimeExpression visitSliceOf(Type t) {
		auto sizet = pass.object.getSizeT().type.builtin;
		Constant[] init =
			[new NullConstant(t.getPointer()), new IntegerConstant(0, sizet)];

		return new ConstantExpression(location,
		                              new SplatConstant(t.getSlice(), init));
	}

	CompileTimeExpression visitArrayOf(uint size, Type t) {
		auto e = visit(t);
		if (auto ce = cast(ConstantExpression) e) {
			Constant[] elements;
			elements.length = size;
			elements[] = ce.value;

			return new ConstantExpression(location,
			                              new ArrayConstant(t, elements));
		}

		CompileTimeExpression[] elements;
		elements.length = size;
		elements[] = e;

		return new CompileTimeTupleExpression(location, t.getArray(size),
		                                      elements);
	}

	CompileTimeExpression visit(Struct s) {
		scheduler.require(s, Step.Signed);

		import source.name;
		auto init = cast(Variable) s.resolve(location, BuiltinName!"init");
		assert(init, "init must be defined");

		scheduler.require(init);

		auto v = cast(CompileTimeExpression) init.value;
		assert(v, "init must be a compile time expressionf");

		return v;
	}

	CompileTimeExpression visit(Union u) {
		// FIXME: Computing this properly would require layout
		// informations from the backend. Will do for now.
		return new ConstantExpression(location, new VoidConstant(Type.get(u)));
	}

	CompileTimeExpression visit(Class c) {
		return new ConstantExpression(location, new NullConstant(Type.get(c)));
	}

	CompileTimeExpression visit(Interface i) {
		Constant[] init =
			[new NullConstant(Type.get(pass.object.getObject())),
			 new NullConstant(Type.get(BuiltinType.Void).getPointer())];

		return new ConstantExpression(location, new AggregateConstant(i, init));
	}

	CompileTimeExpression visit(Enum e) {
		assert(0, "Not implemented.");
	}

	CompileTimeExpression visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}

	CompileTimeExpression visit(Function f) {
		assert(0, "Not implemented.");
	}

	CompileTimeExpression visit(Type[] splat) {
		import std.algorithm, std.array;
		auto elements = splat.map!(t => visit(t)).array();

		Constant[] constants;
		foreach (e; elements) {
			if (auto ce = cast(ConstantExpression) e) {
				constants ~= ce.value;
				continue;
			}

			return new CompileTimeTupleExpression(location, Type.get(splat),
			                                      elements);
		}

		return new ConstantExpression(
			location, new SplatConstant(Type.get(splat), constants));
	}

	CompileTimeExpression visit(ParamType t) {
		assert(!t.isRef, "ref initializer is not implemented.");

		return visit(t.getType());
	}

	CompileTimeExpression visit(FunctionType f) {
		if (f.contexts.length == 0) {
			return
				new ConstantExpression(location, new NullConstant(f.getType()));
		}

		assert(f.contexts.length == 1,
		       "delegate initializer is not implemented.");

		auto elements = [visit(f.contexts[0]), visit(f.getFunction())];
		return new CompileTimeTupleExpression(location, f.getType(), elements);
	}

	CompileTimeExpression visit(Pattern p) {
		assert(0, "Patterns have no initializer.");
	}

	CompileTimeExpression visit(CompileError e) {
		return e.expression;
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
		return InitBuilder(pass, location).visit(t);
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
		auto fields = c.fields.map!(function Expression(f) {
			return f.value;
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
