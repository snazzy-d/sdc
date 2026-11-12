module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.constant;
import d.ir.error;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;
import d.ir.value;

import source.location;

alias InstanceBuilder = DefaultInitializerVisitor!false;
alias NewBuilder = DefaultInitializerVisitor!true;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

/**
 * A default value refers to nothing, so it can have the qualifier of what it
 * initializes.
 */
private Value qualify(SemanticPass pass, Location location, TypeQualifier q,
                      Value value) {
	import d.semantic.caster;
	return buildExplicitCast(pass, location, value.type.qualify(q), value);
}

struct InitBuilder {
	private SemanticPass pass;
	alias pass this;

	Location location;

	this(SemanticPass pass, Location location) {
		this.pass = pass;
		this.location = location;
	}

	/**
	 * The default value of something of type t, which has the qualifier of
	 * what it initializes.
	 */
	Value asValue(T)(T t) {
		auto value = Value.withValue(visit(t));
		static if (is(T : Type)) {
			value = qualify(pass, location, t.qualifier, value);
		}

		return value;
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
		// The default value of an enum is its first member.
		scheduler.require(e);

		auto first = e.entries[0];
		scheduler.require(first);
		return first.value;
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

	Value visit(Type t) {
		return qualify(pass, location, t.qualifier, t.accept(this));
	}

	Expression buildExpression(Type t) {
		return visit(t).getExpression(location);
	}

	Value getDefaultInit(T)(T t) {
		return InitBuilder(pass, location).asValue(t);
	}

	Value visit(BuiltinType t) {
		return getDefaultInit(t);
	}

	Value visitPointerOf(Type t) {
		return getDefaultInit(t);
	}

	Value visitSliceOf(Type t) {
		return getDefaultInit(t);
	}

	Value visitArrayOf(uint size, Type t) {
		Expression[] elements;
		elements.length = size;
		elements[] = buildExpression(t);

		return Value.withValue(
			build!TupleExpression(location, t.getArray(size), elements));
	}

	Value visit(Struct s) {
		auto value = getDefaultInit(s);
		if (!s.hasContext) {
			return value;
		}

		import d.semantic.expression;
		auto v = ExpressionVisitor(pass)
			.getTemporary(value.getExpression(location)).getAddress(location)
			.getExpression(location);

		auto ctxField = s.fields[0];

		import source.name;
		assert(ctxField.name == BuiltinName!"__ctx",
		       "Expected context as first field!");

		auto ctxType = ctxField.type;
		assert(ctxType.kind == TypeKind.Pointer);

		// FIXME: It's be good to have a builder for this.
		auto ctx = build!ContextExpression(location, ctxType.element.context);
		auto field = build!FieldExpression(location, v, ctxField);
		auto assign = build!StoreExpression(location, ctx, field);

		auto t = Type.get(s);
		return Value.withValue(
			build!BinaryExpression(location, t, BinaryOp.Comma, assign,
			                       build!LoadExpression(location, t, v)));
	}

	Value visit(Union u) {
		// FIXME: Computing this properly would require layout
		// informations from the backend. Will do for now.
		return Value.withValue(new VoidConstant(Type.get(u)));
	}

	Value visit(Class c) {
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

				fields[f.index] =
					new ContextExpression(location, ft.element.context);
			}
		}

		return Value.withValue(build!TupleExpression(
			location, Type.get(fields.map!(f => f.type).array()), fields));
	}

	Value visit(Interface i) {
		return getDefaultInit(i);
	}

	Value visit(Enum e) {
		return getDefaultInit(e);
	}

	Value visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}

	Value visit(Function f) {
		return getDefaultInit(f);
	}

	Value visit(Type[] splat) {
		import std.algorithm, std.array;
		auto elements = splat.map!(t => buildExpression(t)).array();

		return Value.withValue(
			build!TupleExpression(location, Type.get(splat), elements));
	}

	Value visit(ParamType t) {
		assert(!t.isRef, "ref initializer is not implemented.");

		return visit(t.getType());
	}

	Value visit(FunctionType f) {
		if (f.contexts.length == 0) {
			return getDefaultInit(f);
		}

		assert(f.contexts.length == 1,
		       "delegate initializer is not implemented.");

		auto elements = [visit(f.contexts[0]).getExpression(location),
		                 visit(f.getFunction()).getExpression(location)];
		return Value
			.withValue(build!TupleExpression(location, f.getType(), elements));
	}

	Value visit(Pattern p) {
		return getDefaultInit(p);
	}

	Value visit(CompileError e) {
		return getDefaultInit(e);
	}
}
