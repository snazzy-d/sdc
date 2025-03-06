module d.semantic.expression;

import d.semantic.caster;
import d.semantic.semantic;

import d.ast.expression;
import d.ast.type;

import d.ir.constant;
import d.ir.error;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;

import source.exception;

struct ExpressionVisitor {
	private SemanticPass pass;
	alias pass this;

	this(SemanticPass pass) {
		this.pass = pass;
	}

	Expression visit(AstExpression e) {
		return this.dispatch!((e) {
			import std.format;
			throw new CompileException(
				e.location, format!"%s is not supported."(typeid(e)));
		})(e);
	}

	Expression visit(ParenExpression e) {
		return visit(e.expr);
	}

	Expression visit(BooleanLiteral e) {
		return new ConstantExpression(e.location, new BooleanConstant(e.value));
	}

	Expression visit(IntegerLiteral e) {
		return new ConstantExpression(e.location,
		                              new IntegerConstant(e.value, e.type));
	}

	Expression visit(FloatLiteral e) {
		return new ConstantExpression(e.location,
		                              new FloatConstant(e.value, e.type));
	}

	Expression visit(CharacterLiteral e) {
		return new ConstantExpression(e.location,
		                              new CharacterConstant(e.value, e.type));
	}

	Expression visit(NullLiteral e) {
		return new ConstantExpression(e.location, new NullConstant());
	}

	Expression visit(StringLiteral e) {
		return new ConstantExpression(e.location, new StringConstant(e.value));
	}

private:
	ErrorExpression getError(T...)(T ts, Location location, string msg) {
		return .getError(ts, location, msg).expression;
	}

	ErrorExpression getError(Expression base, string msg) {
		return getError(base, base.location, msg);
	}

	Expression getTemporary(Expression value) {
		if (auto e = cast(ErrorExpression) value) {
			return e;
		}

		auto loc = value.location;

		import source.name;
		auto v = new Variable(loc, value.type, BuiltinName!"", value);
		v.step = Step.Processed;

		return new VariableExpression(loc, v);
	}

	Expression getLvalue(Expression value) {
		if (auto e = cast(ErrorExpression) value) {
			return e;
		}

		import source.name;
		auto v =
			new Variable(value.location, value.type.getParamType(ParamKind.Ref),
			             BuiltinName!"", value);

		v.step = Step.Processed;
		return new VariableExpression(value.location, v);
	}

	auto buildAssign(Location location, Expression lhs, Expression rhs) {
		if (!lhs.isLvalue) {
			return getError(lhs, "Expected an lvalue.");
		}

		auto type = lhs.type;
		rhs = buildImplicitCast(pass, rhs.location, type, rhs);
		return
			build!BinaryExpression(location, type, BinaryOp.Assign, lhs, rhs);
	}

	Expression buildBinary(Location location, AstBinaryOp op, Expression lhs,
	                       Expression rhs) {
		if (op.isAssign()) {
			lhs = getLvalue(lhs);
			rhs = getTemporary(rhs);

			auto type = lhs.type;
			auto llhs = build!BinaryExpression(location, type, BinaryOp.Comma,
			                                   rhs, lhs);

			return buildAssign(
				location,
				lhs,
				buildExplicitCast(
					pass, location, type,
					buildBinary(location, op.getBaseOp(), llhs, rhs))
			);
		}

		Type type;
		BinaryOp bop;
		ICmpOp icmpop;
		final switch (op) with (AstBinaryOp) {
			case Comma:
				return build!BinaryExpression(location, rhs.type,
				                              BinaryOp.Comma, lhs, rhs);

			case Assign:
				return buildAssign(location, lhs, rhs);

			case Add, Sub:
				auto isSub = op == Sub;
				auto isAdd = op == Add;

				auto lct = lhs.type.getCanonical();
				auto rct = rhs.type.getCanonical();

				auto isLPtr = lct.kind == TypeKind.Pointer;
				auto isRPtr = rct.kind == TypeKind.Pointer;

				// This is a good old add/sub.
				if (!isLPtr && !isRPtr) {
					goto TransparentBinaryOp;
				}

				// Add is commutative, put the pointer on the lhs.
				if (isAdd && !isLPtr && isRPtr) {
					import std.algorithm;
					swap(lhs, rhs);
					swap(lct, rct);
					swap(isLPtr, isRPtr);
				}

				// Pointer arithmetic.
				if (!isRPtr) {
					auto t = pass.object.getSizeT().type;
					auto index = buildImplicitCast(pass, rhs.location, t, rhs);
					if (isSub) {
						index = build!UnaryExpression(rhs.location, t,
						                              UnaryOp.Minus, index);
					}

					auto i = build!IndexExpression(location, lct.element, lhs,
					                               index);
					return build!UnaryExpression(location, lhs.type,
					                             UnaryOp.AddressOf, i);
				}

				// Pointer difference.
				if (isSub && isLPtr && isRPtr) {
					auto t = pass.object.getPtrDiffT().type;
					lhs = buildExplicitCast(pass, lhs.location, t, lhs);
					rhs = buildExplicitCast(pass, rhs.location, t, rhs);

					auto d = build!BinaryExpression(location, t, BinaryOp.Sub,
					                                lhs, rhs);

					import d.semantic.typepromotion;
					auto etype = getPromotedType(pass, location, lct, rct);

					import d.semantic.sizeof;
					auto isize = SizeofVisitor(pass).visit(etype.element);
					auto esize = new ConstantExpression(
						location, new IntegerConstant(isize, t.builtin));

					return build!BinaryExpression(location, t, BinaryOp.SDiv, d,
					                              esize);
				}

				return getError(rhs, lhs, location, "Invalid operand types.");

			case Mul, Pow:
				goto TransparentBinaryOp;

			TransparentBinaryOp:
				import d.common.binaryop;
				bop = getTransparentBinaryOp(op);
				goto PromotedBinaryOp;

			case Div, Rem:
				import d.semantic.typepromotion;
				type = getPromotedType(pass, location, lhs.type, rhs.type);

				auto bt = type.builtin;
				auto signed = isIntegral(bt) && isSigned(bt);

				import d.common.binaryop;
				bop = getSignedBinaryOp(op, signed);
				goto CastBinaryOp;

			case Or, And, Xor:
			case LeftShift, UnsignedRightShift:
				import d.common.binaryop;
				bop = getBitwizeBinaryOp(op);
				goto PromotedBinaryOp;

			PromotedBinaryOp:
				import d.semantic.typepromotion;
				type = getPromotedType(pass, location, lhs.type, rhs.type);

				goto CastBinaryOp;

			case SignedRightShift:
				import d.semantic.typepromotion;
				type = getPromotedType(pass, location, lhs.type, rhs.type);

				auto bt = type.builtin;
				bop = (isIntegral(bt) && isSigned(bt))
					? BinaryOp.SignedRightShift
					: BinaryOp.UnsignedRightShift;

				goto CastBinaryOp;

			case LogicalOr, LogicalAnd:
				type = Type.get(BuiltinType.Bool);

				import d.common.binaryop;
				bop = getLogicalBinaryOp(op);

				lhs = buildExplicitCast(pass, lhs.location, type, lhs);
				rhs = buildExplicitCast(pass, rhs.location, type, rhs);

				goto BuildBinaryOp;

			CastBinaryOp:
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);

				goto BuildBinaryOp;

			BuildBinaryOp:
				return build!BinaryExpression(location, type, bop, lhs, rhs);

			case Concat:
				type = lhs.type;
				if (type.getCanonical().kind != TypeKind.Slice) {
					return getError(lhs, "Expected a slice.");
				}

				rhs = buildImplicitCast(
					pass,
					rhs.location,
					(rhs.type.getCanonical().kind == TypeKind.Slice)
						? type
						: type.element,
					rhs
				);

				auto concat = pass.object.getArrayConcat();
				return callTemplate(location, concat, [lhs, rhs]);

			case AddAssign, SubAssign:
			case MulAssign, PowAssign:
			case DivAssign, RemAssign:
			case OrAssign, AndAssign, XorAssign:
			case LeftShiftAssign:
			case UnsignedRightShiftAssign:
			case SignedRightShiftAssign:
			case LogicalOrAssign:
			case LogicalAndAssign:
			case ConcatAssign:
				assert(0, "Assign op should not reach this point!");

			case Equal, Identical:
				icmpop = ICmpOp.Equal;
				goto HandleICmp;

			case NotEqual, NotIdentical:
				icmpop = ICmpOp.NotEqual;
				goto HandleICmp;

			case GreaterThan:
				icmpop = ICmpOp.GreaterThan;
				goto HandleICmp;

			case GreaterEqual:
				icmpop = ICmpOp.GreaterEqual;
				goto HandleICmp;

			case SmallerThan:
				icmpop = ICmpOp.SmallerThan;
				goto HandleICmp;

			case SmallerEqual:
				icmpop = ICmpOp.SmallerEqual;
				goto HandleICmp;

			HandleICmp:
				import d.semantic.typepromotion;
				type = getPromotedType(pass, location, lhs.type, rhs.type);

				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);

				return build!ICmpExpression(location, icmpop, lhs, rhs);

			case In:
			case NotIn:
				assert(0, "in and !in are not implemented.");

			case LessGreater:
			case LessEqualGreater:
			case UnorderedLess:
			case UnorderedLessEqual:
			case UnorderedGreater:
			case UnorderedGreaterEqual:
			case Unordered:
			case UnorderedEqual:
				assert(0, "Unorderd comparisons are not implemented.");
		}
	}

public:
	Expression visit(AstBinaryExpression e) {
		return buildBinary(e.location, e.op, visit(e.lhs), visit(e.rhs));
	}

	Expression visit(AstTernaryExpression e) {
		auto condition =
			buildExplicitCast(pass, e.condition.location,
			                  Type.get(BuiltinType.Bool), visit(e.condition));

		auto ifTrue = visit(e.ifTrue);
		auto ifFalse = visit(e.ifFalse);

		import d.semantic.typepromotion;
		auto t = getPromotedType(pass, e.location, ifTrue.type, ifFalse.type);

		ifTrue = buildExplicitCast(pass, ifTrue.location, t, ifTrue);
		ifFalse = buildExplicitCast(pass, ifFalse.location, t, ifFalse);

		return
			build!TernaryExpression(e.location, t, condition, ifTrue, ifFalse);
	}

	private Expression handleAddressOf(Expression expr) {
		// For fucked up reasons, &funcname is a special case.
		if (matchFunction(expr)) {
			return expr;
		}

		if (auto pe = cast(PolysemousExpression) expr) {
			import std.algorithm, std.array;
			pe.expressions =
				pe.expressions.map!(e => handleAddressOf(e)).array();
			return pe;
		}

		return build!UnaryExpression(expr.location, expr.type.getPointer(),
		                             UnaryOp.AddressOf, expr);
	}

	Expression visit(AstUnaryExpression e) {
		auto expr = visit(e.expr);

		UnaryOp op;
		Type type;
		final switch (e.op) with (AstUnaryOp) {
			case AddressOf:
				op = UnaryOp.AddressOf;
				return handleAddressOf(expr);

			case Dereference:
				op = UnaryOp.Dereference;
				auto c = expr.type.getCanonical();
				if (c.kind == TypeKind.Pointer) {
					type = c.element;
					break;
				}

				return getError(expr, e.location,
				                "Only pointers can be dereferenced.");

			case PreInc:
				op = UnaryOp.PreInc;
				goto IncDecOp;

			case PreDec:
				op = UnaryOp.PreDec;
				goto IncDecOp;

			case PostInc:
				op = UnaryOp.PostInc;
				goto IncDecOp;

			case PostDec:
				op = UnaryOp.PostDec;
				goto IncDecOp;

			IncDecOp:
				// FIXME: check that type is integer or pointer.
				type = expr.type;
				break;

			case Plus:
				op = UnaryOp.Plus;
				goto IntegralOp;

			case Minus:
				op = UnaryOp.Minus;
				goto IntegralOp;

			case Complement:
				op = UnaryOp.Complement;
				goto IntegralOp;

			IntegralOp:
				import d.semantic.typepromotion;
				type = getPromotedType(pass, expr.location, expr.type,
				                       Type.get(BuiltinType.Int));
				expr = buildExplicitCast(pass, expr.location, type, expr);
				break;

			case Not:
				op = UnaryOp.Not;
				type = Type.get(BuiltinType.Bool);
				expr = buildExplicitCast(pass, expr.location, type, expr);
				break;
		}

		return build!UnaryExpression(e.location, type, op, expr);
	}

	Expression visit(AstCastExpression e) {
		import d.semantic.type;
		return buildExplicitCast(
			pass, e.location, TypeVisitor(pass).visit(e.type), visit(e.expr));
	}

	Expression visit(AstArrayLiteral e) {
		import std.algorithm, std.array;
		auto values = e.values.map!(v => visit(v)).array();

		// The type of the first element determine the type of the array.
		auto type =
			values.length > 0 ? values[0].type : Type.get(BuiltinType.Void);

		// Cast all the value to the proper type.
		values = values.map!(v => buildImplicitCast(pass, v.location, type, v))
		               .array();

		return build!ArrayLiteral(e.location, type.getSlice(), values);
	}

	Expression buildArgument(Expression arg, ParamType pt) {
		if (pt.isRef && !canConvert(arg.type.qualifier, pt.qualifier)) {
			import std.format;
			return getError(
				arg,
				format!"Can't pass argument (%s) by ref to %s."(
					arg.type.toString(context), pt.toString(context))
			);
		}

		arg = buildImplicitCast(pass, arg.location, pt.getType(), arg);

		// Test if we can pass by ref.
		if (pt.isRef && !arg.isLvalue) {
			return getError(arg, "Argument isn't a lvalue.");
		}

		return arg;
	}

	enum MatchLevel {
		Not,
		TypeConvert,
		QualifierConvert,
		Exact,
	}

	// TODO: deduplicate.
	private auto matchArgument(Expression arg, ParamType param) {
		if (param.isRef && !canConvert(arg.type.qualifier, param.qualifier)) {
			return MatchLevel.Not;
		}

		auto flavor = implicitCastFrom(pass, arg.type, param.getType());

		// test if we can pass by ref.
		if (param.isRef && !(flavor >= CastKind.Bit && arg.isLvalue)) {
			return MatchLevel.Not;
		}

		return matchLevel(flavor);
	}

	// TODO: deduplicate.
	private auto matchArgument(ParamType type, ParamType param) {
		if (param.isRef && !canConvert(type.qualifier, param.qualifier)) {
			return MatchLevel.Not;
		}

		auto flavor = implicitCastFrom(pass, type.getType(), param.getType());

		// test if we can pass by ref.
		if (param.isRef && !(flavor >= CastKind.Bit && type.isRef)) {
			return MatchLevel.Not;
		}

		return matchLevel(flavor);
	}

	private auto matchLevel(CastKind flavor) {
		final switch (flavor) with (CastKind) {
			case Invalid:
				return MatchLevel.Not;

			case UnsignedToPointer, SignedToPointer, PointerToInt:
			case Down, IntToBool, PointerToBool, Trunc:
			case FloatToSigned, FloatToUnsigned:
				assert(0, "Not an implicit cast!");

			case FloatExtend, FloatTrunc:
			case SignedToFloat, UnsignedToFloat:
				return MatchLevel.TypeConvert;

			case UPad, SPad, Bit:
				return MatchLevel.TypeConvert;

			case Qual:
				return MatchLevel.QualifierConvert;

			case Exact:
				return MatchLevel.Exact;
		}
	}

	private Expression getContext(Location location, Function f)
			in(f.step >= Step.Signed) {
		import d.semantic.closure;
		auto ctx = ContextFinder(pass).visit(f);
		return build!ContextExpression(location, ctx);
	}

	Expression getFrom(Location location, Function f) {
		scheduler.require(f, Step.Signed);

		Expression[] ctxs;
		ctxs.reserve(f.hasThis + f.hasContext);
		if (f.hasContext) {
			ctxs ~= getContext(location, f);
		}

		if (f.hasThis) {
			ctxs ~= getThis(location);
		}

		return getFromImpl(location, f, ctxs);
	}

	Expression getFrom(Location location, Expression thisExpr, Function f) {
		scheduler.require(f, Step.Signed);

		Expression[] ctxs;
		ctxs.reserve(f.hasContext + 1);

		if (f.hasContext) {
			ctxs ~= getContext(location, f);
		}

		ctxs ~= thisExpr;
		return getFromImpl(location, f, ctxs);
	}

	private Expression getFromImpl(Location location, Function f,
	                               Expression[] ctxs) in {
		assert(f.step >= Step.Signed);
		assert(ctxs.length >= f.hasContext + f.hasThis);
	} do {
		foreach (i, ref c; ctxs) {
			c = buildArgument(c, f.type.parameters[i]);
		}

		auto e = (ctxs.length == 0)
			? new ConstantExpression(location, new FunctionConstant(f))
			: build!DelegateExpression(location, ctxs, f);

		// If this is not a property, things are straigforward.
		if (!f.isProperty) {
			return e;
		}

		assert(!f.hasContext);
		if (f.params.length != ctxs.length - f.hasContext) {
			import std.format;
			return getError(
				e,
				format!"Invalid number of argument for @property %s."(
					f.name.toString(context))
			);
		}

		Expression[] args;
		return build!CallExpression(location, f.type.returnType.getType(), e,
		                            args);
	}

	Expression visit(AstCallExpression c) {
		import std.algorithm, std.array;
		auto args = c.arguments.map!(a => visit(a)).array();

		// FIXME: Have a ThisCallExpression.
		auto te = cast(ThisExpression) c.callee;
		if (te is null) {
			return handleCall(c.location, visit(c.callee), args);
		}

		// FIXME: check if we are in a constructor.
		auto t = thisType.getType().getCanonical();
		if (!t.isAggregate()) {
			assert(0, "ctor on non aggregate not implemented!");
		}

		auto loc = c.callee.location;
		auto thisExpr = getThis(loc);

		auto ctor = findCtor(c.location, loc, thisExpr, args);
		auto thisKind = ctor.type.asFunctionType().contexts[0].paramKind;
		auto call = callCallable(c.location, ctor, args);

		final switch (thisKind) with (ParamKind) {
			case Regular:
				// Value type, by value.
				return build!BinaryExpression(c.location, thisExpr.type,
				                              BinaryOp.Assign, thisExpr, call);

			case Final:
				// Classes.
				return call;

			case Ref:
				// Value type, by ref.
				return build!BinaryExpression(c.location, thisExpr.type,
				                              BinaryOp.Comma, call, thisExpr);
		}
	}

	Expression visit(IdentifierCallExpression c) {
		import std.algorithm, std.array;
		auto args = c.arguments.map!(a => visit(a)).array();

		// XXX: Why are doing this here ?
		// Shouldn't this be done in the identifier module ?
		Expression postProcess(T)(T identified) {
			static if (is(T : Expression)) {
				return handleCall(c.location, identified, args);
			} else {
				static if (is(T : Symbol)) {
					if (auto s = cast(OverloadSet) identified) {
						return callOverloadSet(c.location, s, args);
					}

					if (auto t = cast(Template) identified) {
						return callTemplate(c.location, t, args);
					}
				}

				static if (is(T : Type)) {
					return callType(c.location, c.callee.location, identified,
					                args);
				} else {
					import std.format;
					return getError(
						identified,
						c.location,
						format!"%s isn't callable."(
							c.callee.toString(pass.context))
					);
				}
			}
		}

		import d.ast.identifier, d.semantic.identifier;
		if (auto tidi = cast(TemplateInstantiation) c.callee) {
			// XXX: For some reason this need to be passed a lambda.
			return IdentifierResolver(pass).build(tidi, args)
			                               .apply!(i => postProcess(i))();
		}

		// XXX: For some reason this need to be passed a lambda.
		return IdentifierResolver(pass).build(c.callee)
		                               .apply!((i => postProcess(i)))();
	}

	Expression visit(TypeCallExpression e) {
		import d.semantic.type;
		auto t = TypeVisitor(pass).visit(e.type);

		import std.algorithm, std.array;
		auto args = e.arguments.map!(a => visit(a)).array();

		return callType(e.location, e.location, t, args);
	}

	private Expression callType(Location location, Location calleeLoc,
	                            Type callee, Expression[] args) {
		auto t = callee.getCanonical();
		switch (t.kind) with (TypeKind) {
			case Builtin:
				if (args.length == 1) {
					return buildImplicitCast(pass, location, t, args[0]);
				}

				return getError(t, location, "Expected one argument.");

			case Struct:
				auto s = t.dstruct;
				scheduler.require(s, Step.Signed);

				import d.semantic.defaultinitializer;
				auto di = InstanceBuilder(pass, calleeLoc).visit(s);
				if (s.isSmall) {
					return callCtor(location, calleeLoc, di, args);
				}

				auto thisExpr = getTemporary(di);
				return build!BinaryExpression(
					location, t, BinaryOp.Comma,
					callCtor(location, calleeLoc, thisExpr, args), thisExpr);

			default:
				return getError(t, location, "Cannot build this type.");
		}
	}

	private Expression callCtor(
		Location location,
		Location calleeLoc,
		Expression thisExpr,
		Expression[] args
	) in(thisExpr.type.isAggregate()) {
		auto ctor = findCtor(location, calleeLoc, thisExpr, args);
		return callCallable(location, ctor, args);
	}

	// XXX: factorize with NewExpression
	private Expression findCtor(Location location, Location calleeLoc,
	                            Expression thisExpr, Expression[] args) in {
		import std.format;
		assert(thisExpr.type.isAggregate(),
		       format!"%s is not an aggregate!"(thisExpr.toString(context)));
	} do {
		auto agg = thisExpr.type.aggregate;

		import source.name, d.semantic.identifier;
		return IdentifierResolver(pass)
			.resolveIn(location, agg, BuiltinName!"__ctor")
			.apply!(delegate Expression(i) {
				alias T = typeof(i);
				static if (is(T : Symbol)) {
					if (auto f = cast(Function) i) {
						return getFrom(calleeLoc, thisExpr, f);
					}

					if (auto s = cast(OverloadSet) i) {
						// FIXME: overload resolution doesn't do alias this
						// or vrp trunc, so we need a workaround here.
						if (s.set.length == 1) {
							if (auto f = cast(Function) s.set[0]) {
								return getFrom(calleeLoc, thisExpr, f);
							}
						}

						import std.algorithm, std.array;
						return chooseOverload(
							location, s.set.map!(delegate Expression(s) {
								if (auto f = cast(Function) s) {
									return getFrom(calleeLoc, thisExpr, f);
								}

								// XXX: Template ??!?!!?
								assert(0, "Not a constructor!");
							}).array(), args);
					}
				}

				import std.format;
				return getError(
					i,
					location,
					format!"%s isn't callable."(agg.name.toString(pass.context))
				);
			})();
	}

	private
	Expression handleIFTI(Location location, Template t, Expression[] args) {
		import d.semantic.dtemplate;
		TemplateArgument[] targs;
		targs.length = t.parameters.length;

		auto i = TemplateInstancier(pass).instanciate(location, t, [], args);
		scheduler.require(i);

		import d.semantic.identifier;
		return IdentifierResolver(
			pass
		).buildIn(location, i, t.name).apply!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return identified;
			} else {
				import std.format;
				return getError(
					identified, location,
					format!"%s isn't callable."(t.name.toString(pass.context)));
			}
		})();
	}

	private
	auto callTemplate(Location location, Template t, Expression[] args) {
		auto callee = handleIFTI(location, t, args);
		return callCallable(location, callee, args);
	}

	private Expression callOverloadSet(Location location, OverloadSet s,
	                                   Expression[] args) {
		import std.algorithm, std.array;
		return callCallable(location, chooseOverload(location, s.set.map!((s) {
			pass.scheduler.require(s, Step.Signed);
			if (auto f = cast(Function) s) {
				return getFrom(location, f);
			} else if (auto t = cast(Template) s) {
				return handleIFTI(location, t, args);
			}

			import std.format;
			throw new CompileException(
				s.location,
				format!"%s is not supported in overload set."(typeid(s))
			);
		}).array(), args), args);
	}

	private static bool checkArgumentCount(bool isVariadic, size_t argCount,
	                                       size_t paramCount) {
		return isVariadic ? argCount >= paramCount : argCount == paramCount;
	}

	// XXX: Take a range instead of an array.
	private
	Expression chooseOverload(Location location, Expression[] candidates,
	                          Expression[] args) {
		import std.algorithm, std.range;
		auto cds =
			candidates.map!(e => findCallable(location, e, args)).filter!((e) {
				auto t = e.type.getCanonical();

				import std.format;
				assert(
					t.kind == TypeKind.Function,
					format!"%s is not a function type."(
						e.type.toString(pass.context))
				);

				auto ft = t.asFunctionType();
				return checkArgumentCount(ft.isVariadic, args.length,
				                          ft.parameters.length);
			});

		auto level = MatchLevel.Not;
		Expression match;
		CandidateLoop: foreach (candidate; cds) {
			auto t = candidate.type.getCanonical();
			assert(t.kind == TypeKind.Function,
			       "We should have filtered function at this point.");

			auto funType = t.asFunctionType();

			auto candidateLevel = MatchLevel.Exact;
			foreach (arg, param; lockstep(args, funType.parameters)) {
				auto argLevel = matchArgument(arg, param);

				// If we don't match high enough.
				if (argLevel < level) {
					continue CandidateLoop;
				}

				final switch (argLevel) with (MatchLevel) {
					case Not:
						// This function don't match, go to next one.
						continue CandidateLoop;

					case TypeConvert, QualifierConvert:
						candidateLevel = min(candidateLevel, argLevel);
						continue;

					case Exact:
						// Go to next argument
						continue;
				}
			}

			if (candidateLevel > level) {
				level = candidateLevel;
				match = candidate;
			} else if (candidateLevel == level) {
				// Check for specialisation.
				auto mt = match.type.getCanonical();
				assert(mt.kind == TypeKind.Function,
				       "We should have filtered function at this point.");

				auto prange = lockstep(funType.parameters,
				                       mt.asFunctionType().parameters);

				bool candidateFail;
				bool matchFail;
				foreach (param, matchParam; prange) {
					if (matchArgument(param, matchParam) == MatchLevel.Not) {
						candidateFail = true;
					}

					if (matchArgument(matchParam, param) == MatchLevel.Not) {
						matchFail = true;
					}
				}

				if (matchFail == candidateFail) {
					return getError(candidate, location,
					                "Ambiguous function call.");
				}

				if (matchFail) {
					match = candidate;
				}
			}
		}

		if (match) {
			return match;
		}

		return getError(location, "No candidate for function call.");
	}

	private Expression findCallable(Location location, Expression callee,
	                                Expression[] args) {
		if (auto asPolysemous = cast(PolysemousExpression) callee) {
			return chooseOverload(location, asPolysemous.expressions, args);
		}

		auto type = callee.type.getCanonical();
		if (type.kind == TypeKind.Function) {
			return callee;
		}

		import std.algorithm, std.array;
		import d.semantic.aliasthis;
		auto ar = AliasThisResolver!((identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return findCallable(location, identified, args);
			} else {
				return cast(Expression) null;
			}
		})(pass);

		auto results = ar
			.resolve(callee)
			.filter!(e => e !is null && typeid(e) !is typeid(ErrorExpression))
			.array();

		if (results.length == 1) {
			return results[0];
		}

		import std.format;
		return getError(
			callee,
			location,
			format!"You must call function or delegates, not %s."(
				callee.type.toString(context))
		);
	}

	private Expression handleCall(Location location, Expression callee,
	                              Expression[] args) {
		return
			callCallable(location, findCallable(location, callee, args), args);
	}

	private static Function matchFunction(Expression e) {
		if (auto ce = cast(ConstantExpression) e) {
			if (auto fc = cast(FunctionConstant) ce.value) {
				return fc.fun;
			}
		}

		return null;
	}

	private static Function matchFunctionOrDelegate(Expression e) {
		if (auto f = matchFunction(e)) {
			return f;
		}

		if (auto dge = cast(DelegateExpression) e) {
			return dge.method;
		}

		return null;
	}

	// XXX: This assume that calable is the right one,
	// but not all call sites do the check.
	private Expression callCallable(Location location, Expression callee,
	                                Expression[] args) in {
		auto k = callee.type.getCanonical().kind;
		assert(k == TypeKind.Function || k == TypeKind.Error,
		       callee.toString(context));
	} do {
		auto t = callee.type.getCanonical();
		if (t.kind == TypeKind.Error) {
			return callee;
		}

		auto f = t.asFunctionType();

		auto paramTypes = f.parameters;
		auto returnType = f.returnType;

		// If we don't have enough parameters, try to find default
		// values in the function declaration.
		if (args.length < paramTypes.length) {
			Function fun = matchFunctionOrDelegate(callee);
			if (fun is null) {
				// Can't find the function, error.
				return getError(callee, location,
				                "Cannot identify called function.");
			}

			auto start = args.length + f.contexts.length;
			auto stop = paramTypes.length + f.contexts.length;
			auto params = fun.params[start .. stop];
			foreach (p; params) {
				if (p.value is null) {
					return
						getError(callee, location, "Insuffiscient parameters.");
				}

				args ~= p.value;
			}
		} else if (args.length > paramTypes.length && !f.isVariadic) {
			return getError(callee, location, "Too many parameters.");
		}

		import std.range;
		foreach (ref arg, pt; lockstep(args, paramTypes)) {
			arg = buildArgument(arg, pt);
		}

		// If this is an intrinsic, create an intrinsic expression.
		if (auto fun = matchFunction(callee)) {
			if (auto i = fun.intrinsicID) {
				return build!IntrinsicExpression(location, returnType.getType(),
				                                 i, args);
			}
		}

		return
			build!CallExpression(location, returnType.getType(), callee, args);
	}

	// XXX: factorize with findCtor
	Expression visit(AstNewExpression e) {
		import std.algorithm, std.array;
		auto args = e.arguments.map!(a => visit(a)).array();

		import d.semantic.type;
		auto type = TypeVisitor(pass).visit(e.type);

		import d.semantic.defaultinitializer;
		auto di = NewBuilder(pass, e.location).visit(type);
		auto hackForDg = (&di)[0 .. 1];

		import source.name, d.semantic.identifier;
		auto ctor = IdentifierResolver(pass)
			.resolveIn(e.location, type, BuiltinName!"__ctor")
			.apply!(delegate Function(identified) {
				static if (is(typeof(identified) : Symbol)) {
					if (auto f = cast(Function) identified) {
						pass.scheduler.require(f, Step.Signed);
						return f;
					}

					if (auto s = cast(OverloadSet) identified) {
						auto m = chooseOverload(
							e.location, s.set.map!(delegate Expression(s) {
								if (auto f = cast(Function) s) {
									return new DelegateExpression(e.location,
									                              hackForDg, f);
								}

								assert(0, "Not a constructor!");
							}).array(), args);

						// XXX: find a clean way to achieve this.
						return (cast(DelegateExpression) m).method;
					}
				}

				assert(0, "Gimme some construtor!");
			})();

		// First parameter is compiler magic.
		auto parameters = ctor.type.parameters[1 .. $];

		import std.range;
		assert(args.length >= parameters.length);
		foreach (ref arg, pt; lockstep(args, parameters)) {
			arg = buildArgument(arg, pt);
		}

		if (type.getCanonical().kind != TypeKind.Class) {
			type = type.getPointer();
		}

		return build!NewExpression(e.location, type, di, ctor, args);
	}

	Expression getThis(Location location) {
		import source.name, d.semantic.identifier;
		auto thisExpr = IdentifierResolver(pass)
			.build(location, BuiltinName!"this")
			.apply!(delegate Expression(identified) {
				static if (is(typeof(identified) : Expression)) {
					return identified;
				} else {
					return getError(location,
					                "Cannot find a suitable this pointer.");
				}
			})();

		return buildImplicitCast(pass, location, thisType.getType(), thisExpr);
	}

	Expression visit(ThisExpression e) {
		return getThis(e.location);
	}

	Expression getIndex(Location location, Expression indexed,
	                    Expression index) {
		auto t = indexed.type.getCanonical();
		if (!t.hasElement) {
			import std.format;
			return getError(
				indexed, location,
				format!"Can't index %s."(indexed.type.toString(context)));
		}

		index = buildImplicitCast(pass, location, pass.object.getSizeT().type,
		                          index);

		// Make sure we create a temporary for rvalue indices.
		// XXX: Should this be done in the backend ?
		if (t.kind == TypeKind.Array && !indexed.isLvalue) {
			indexed = getTemporary(indexed);
		}

		return build!IndexExpression(location, t.element, indexed, index);
	}

	Expression visit(AstIndexExpression e) {
		auto indexed = visit(e.indexed);

		import std.algorithm, std.array;
		auto arguments = e.arguments.map!(e => visit(e)).array();
		assert(arguments.length == 1,
		       "Multiple argument index are not supported!");

		return getIndex(e.location, indexed, arguments[0]);
	}

	Expression visit(AstSliceExpression e) {
		// TODO: check if it is valid.
		auto sliced = visit(e.sliced);

		auto t = sliced.type.getCanonical();
		if (!t.hasElement) {
			import std.format;
			return getError(sliced, e.location,
			                format!"Can't slice %s."(t.toString(context)));
		}

		assert(e.first.length == 1 && e.second.length == 1);

		auto first = visit(e.first[0]);
		auto second = visit(e.second[0]);

		return build!SliceExpression(e.location, t.element.getSlice(), sliced,
		                             first, second);
	}

	private Expression handleTypeid(Location location, Expression e) {
		auto c = e.type.getCanonical();
		if (c.kind != TypeKind.Class) {
			return getTypeInfo(location, e.type);
		}

		return build!DynamicTypeidExpression(
			location, Type.get(pass.object.getClassInfo()), e);
	}

	Expression getTypeInfo(Location location, Type t) {
		t = t.getCanonical();
		if (t.kind == TypeKind.Class) {
			return getClassInfo(location, t.dclass);
		}

		// FIXME: Have some kind of builder for constant, and make
		//        ErrorExpression a Constant.
		if (auto e = errorize(t)) {
			return e.expression;
		}

		return new ConstantExpression(
			location,
			new TypeidConstant(Type.get(pass.object.getTypeInfo()), t)
		);
	}

	auto getClassInfo(Location location, Class c) {
		return new ConstantExpression(
			location,
			new TypeidConstant(Type.get(pass.object.getClassInfo()),
			                   Type.get(c))
		);
	}

	Expression visit(AstTypeidExpression e) {
		return handleTypeid(e.location, visit(e.argument));
	}

	Expression visit(AstStaticTypeidExpression e) {
		import d.semantic.type;
		return getTypeInfo(e.location, TypeVisitor(pass).visit(e.argument));
	}

	Expression visit(IdentifierTypeidExpression e) {
		import d.semantic.identifier;
		return IdentifierResolver(pass)
			.build(e.argument).apply!(delegate Expression(identified) {
				alias T = typeof(identified);
				static if (is(T : Type)) {
					return getTypeInfo(e.location, identified);
				} else static if (is(T : Expression)) {
					return handleTypeid(e.location, identified);
				} else {
					import std.format;
					return getError(
						identified,
						e.location,
						format!"Can't get typeid of %s."(
							e.argument.toString(pass.context))
					);
				}
			})();
	}

	Expression visit(IdentifierExpression e) {
		import d.semantic.identifier;
		return IdentifierResolver(pass)
			.build(e.identifier).apply!(delegate Expression(identified) {
				alias T = typeof(identified);
				static if (is(T : Expression)) {
					return identified;
				} else {
					static if (is(T : Symbol)) {
						if (auto s = cast(OverloadSet) identified) {
							return buildPolysemous(e.location, s);
						}
					}

					import std.format;
					return getError(
						identified,
						e.location,
						format!"%s isn't an expression."(
							e.identifier.toString(pass.context))
					);
				}
			})();
	}

	private Expression buildPolysemous(Location location, OverloadSet s) {
		import std.algorithm, std.array;
		import d.semantic.identifier;
		auto exprs = s
			.set
			.map!(s => IdentifierResolver(pass)
				.postProcess(location, s)
				.apply!(delegate Expression(identified) {
					alias T = typeof(identified);
					static if (is(T : Expression)) {
						return identified;
					} else static if (is(T : Type)) {
						assert(0, "Type can't be overloaded!");
					} else {
						// TODO: handle templates.
						import std.format;
						throw new CompileException(
							identified.location,
							format!"%s is not supported in overload set."(
								typeid(identified))
						);
					}
				})())
			.array();
		return new PolysemousExpression(location, exprs);
	}

	import d.ast.declaration, d.ast.statement;
	private auto handleDgs(Location location, string prefix, ParamDecl[] params,
	                       bool isVariadic, BlockStatement fbody) {
		// FIXME: can still collide with mixins,
		// but that should rare enough for now.
		import std.conv;
		auto offset = location.getFullLocation(context).getStartOffset();
		auto name = context.getName(prefix ~ offset.to!string());

		auto d = new FunctionDeclaration(
			location,
			defaultStorageClass,
			AstType.getAuto().getParamType(ParamKind.Regular),
			name,
			params,
			isVariadic,
			fbody
		);

		auto f =
			new Function(location, currentScope, FunctionType.init, name, []);

		f.hasContext = true;

		import d.semantic.symbol;
		SymbolAnalyzer(pass).analyze(d, f);
		scheduler.require(f);

		return getFrom(location, f);
	}

	Expression visit(DelegateLiteral e) {
		return handleDgs(e.location, "__dg", e.params, e.isVariadic, e.fbody);
	}

	Expression visit(Lambda e) {
		auto v = e.value;
		return handleDgs(
			e.location,
			"__lambda",
			e.params,
			false,
			new BlockStatement(v.location, [new ReturnStatement(v.location, v)])
		);
	}

	import d.ast.conditional;
	Expression visit(Mixin!AstExpression e) {
		import d.semantic.evaluator;
		auto str = evalString(visit(e.value));
		auto pos = context.registerMixin(e.location, str);

		import source.dlexer;
		auto trange = lex(pos, context);

		import d.parser.base, d.parser.expression;
		trange.match(TokenType.Begin);
		return visit(trange.parseExpression());
	}
}
