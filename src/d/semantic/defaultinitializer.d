module d.semantic.defaultinitializer;

import d.semantic.semantic;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;

alias InitBuilder = DefaultInitializerVisitor!(true, false);
alias InstanceBuilder = DefaultInitializerVisitor!(false, false);
alias NewBuilder = DefaultInitializerVisitor!(false, true);

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

private:
struct DefaultInitializerVisitor(bool isCompileTime, bool isNew) {
	static assert(!isCompileTime || !isNew);

	static if (isCompileTime) {
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
		final switch (t) with (BuiltinType) {
			case None, Void:
				import d.ir.error;
				return new CompileError(
					location,
					Type.get(t).toString(context)
						~ " has no default initializer"
				).expression;

			case Bool:
				return new BooleanLiteral(location, false);

			case Char, Wchar, Dchar:
				return new CharacterLiteral(location, getCharInit(t), t);

			case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent,
			     Ucent:
				return new IntegerLiteral(location, 0, t);

			case Float, Double, Real:
				return new FloatLiteral(location, float.nan, t);

			case Null:
				return new NullLiteral(location);
		}
	}

	E visitPointerOf(Type t) {
		return new NullLiteral(location, t.getPointer());
	}

	E visitSliceOf(Type t) {
		auto sizet = pass.object.getSizeT().type.builtin;
		CompileTimeExpression[] init =
			[new NullLiteral(location, t.getPointer()),
			 new IntegerLiteral(location, 0UL, sizet)];

		// XXX: Should cast to size_t, but buildImplicitCast
		// doesn't produce CompileTimeExpressions.
		return new CompileTimeTupleExpression(location, t.getSlice(), init);
	}

	E visitArrayOf(uint size, Type t) {
		E[] elements;
		elements.length = size;
		elements[] = visit(t);

		static if (isCompileTime) {
			return new CompileTimeTupleExpression(location, t.getArray(size),
			                                      elements);
		} else {
			return build!TupleExpression(location, t.getArray(size), elements);
		}
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

	E visit(Struct s) {
		scheduler.require(s, Step.Signed);

		import source.name;
		auto init = cast(Variable) s.resolve(location, BuiltinName!"init");
		assert(init, "init must be defined");

		scheduler.require(init);

		static if (isCompileTime) {
			auto v = cast(E) init.value;
			assert(v, "init must be a compile time expression");

			return v;
		} else {
			auto v = init.value;
			if (!s.hasContext) {
				return v;
			}

			v = getTemporary(v);

			auto ctxField = s.fields[0];
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
	}

	E visit(Union u) {
		// FIXME: Computing this properly would require layout
		// informations from the backend. Will do for now.
		return new VoidInitializer(location, Type.get(u));
	}

	E visit(Class c) {
		static if (isNew) {
			scheduler.require(c);

			import std.algorithm, std.array;
			auto fields = c.fields.map!(function Expression(f) {
				return f.value;
			}).array();

			fields[0] = new StaticTypeidExpression(
				location, Type.get(pass.object.getTypeInfo()), Type.get(c));
			if (c.hasContext) {
				import std.algorithm;
				import source.name;
				auto ctxr =
					c.fields.filter!(f => f.name == BuiltinName!"__ctx");

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
		} else {
			return new NullLiteral(location, Type.get(c));
		}
	}

	E visit(Interface i) {
		CompileTimeExpression[] init = [
			new NullLiteral(location, Type.get(pass.object.getObject())),
			new NullLiteral(location, Type.get(BuiltinType.Void).getPointer())
		];

		return new CompileTimeTupleExpression(location, Type.get(i), init);
	}

	E visit(Enum e) {
		assert(0, "Not implemented");
	}

	E visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}

	E visit(Function f) {
		assert(0, "Not implemented");
	}

	E visit(Type[] seq) {
		import std.algorithm, std.array;
		auto elements = seq.map!(t => visit(t)).array();

		static if (isCompileTime) {
			return new CompileTimeTupleExpression(location, Type.get(seq),
			                                      elements);
		} else {
			return build!TupleExpression(location, Type.get(seq), elements);
		}
	}

	E visit(ParamType t) {
		assert(!t.isRef, "ref initializer is not implemented.");

		return visit(t.getType());
	}

	E visit(FunctionType f) {
		if (f.contexts.length == 0) {
			return new NullLiteral(location, f.getType());
		}

		assert(f.contexts.length == 1,
		       "delegate initializer is not implemented.");

		auto elements = [visit(f.contexts[0]), visit(f.getFunction())];

		static if (isCompileTime) {
			return
				new CompileTimeTupleExpression(location, f.getType(), elements);
		} else {
			return build!TupleExpression(location, f.getType(), elements);
		}
	}

	E visit(Pattern p) {
		assert(0, "Patterns have no initializer.");
	}

	import d.ir.error;
	E visit(CompileError e) {
		return e.expression;
	}
}
