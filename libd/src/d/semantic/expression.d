module d.semantic.expression;

import d.semantic.caster;
import d.semantic.identifier;
import d.semantic.semantic;

import d.ast.expression;
import d.ast.type;

import d.ir.dscope;
import d.ir.error;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.context.location;

import d.exception;

alias TernaryExpression = d.ir.expression.TernaryExpression;
alias BinaryExpression = d.ir.expression.BinaryExpression;
alias CallExpression = d.ir.expression.CallExpression;
alias NewExpression = d.ir.expression.NewExpression;
alias AssertExpression = d.ir.expression.AssertExpression;

struct ExpressionVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Expression visit(AstExpression e) {
		return this.dispatch!((e) {
			throw new CompileException(e.location, typeid(e).toString() ~ " is not supported");
		})(e);
	}
	
	Expression visit(ParenExpression e) {
		return visit(e.expr);
	}
	
	Expression visit(BooleanLiteral e) {
		return e;
	}
	
	Expression visit(IntegerLiteral e) {
		return e;
	}
	
	Expression visit(FloatLiteral e) {
		return e;
	}
	
	Expression visit(CharacterLiteral e) {
		return e;
	}
	
	Expression visit(NullLiteral e) {
		return e;
	}
	
	Expression visit(StringLiteral e) {
		return e;
	}
	
	private ErrorExpression getError(Expression base, Location location, string msg) {
		if (auto e = cast(ErrorExpression) base) {
			return e;
		}
		
		return new CompileError(location, msg).expression;
	}
	
	private ErrorExpression getError(Expression base, string msg) {
		return getError(base, base.location, msg);
	}
	
	private ErrorExpression getError(Symbol base, Location location, string msg) {
		if (auto e = cast(ErrorSymbol) base) {
			return e.error.expression;
		}
		
		return new CompileError(location, msg).expression;
	}
	
	private ErrorExpression getError(Type t, Location location, string msg) {
		if (t.kind == TypeKind.Error) {
			return t.error.expression;
		}
		
		return new CompileError(location, msg).expression;
	}
	
	private Expression getLvalue(Expression value) {
		if (auto e = cast(ErrorExpression) value) {
			return e;
		}
		
		import d.context.name;
		auto v = new Variable(value.location, value.type.getParamType(true, false), BuiltinName!"", value);
		v.step = Step.Processed;
		
		return new VariableExpression(value.location, v);
	}
	
	Expression build(E, T...)(T args) if (is(typeof(new E(T.init)))) {
		foreach (ref a; args) {
			alias T = typeof(a);
			static if (is(T : Expression)) {
				if (auto e = cast(ErrorExpression) a) {
					return e;
				}
			} else static if (is(T : U[], U : Expression)) {
				foreach (e; a) {
					if (auto ee = cast(ErrorExpression) e) {
						return ee;
					}
				}
			}
		}
		
		foreach (ref a; args) {
			static if (is(typeof(a) : Type)) {
				if (a.kind == TypeKind.Error) {
					return a.error.expression;
				}
			}
		}
		
		// XXX: ErrorSymbol ???
		return new E(args);
	}
	
	Expression visit(AstBinaryExpression e) {
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		auto op = e.op;
		
		Type type;
		final switch(op) with(BinaryOp) {
			case Comma:
				type = rhs.type;
				break;
			
			case Assign :
				if (!lhs.isLvalue) {
					return getError(lhs, "Expected an lvalue");
				}
				
				type = lhs.type;
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				break;
			
			case Add :
			case Sub :
				auto c = lhs.type.getCanonical();
				if (c.kind == TypeKind.Pointer) {
					// FIXME: check that rhs is an integer.
					if (op == Sub) {
						rhs = new UnaryExpression(rhs.location, rhs.type, UnaryOp.Minus, rhs);
					}
					
					auto i = new IndexExpression(e.location, c.element, lhs, rhs);
					return new UnaryExpression(e.location, lhs.type, UnaryOp.AddressOf, i);
				}
				
				goto case;
			
			case Mul :
			case Div :
			case Mod :
			case Pow :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type, rhs.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case AddAssign :
			case SubAssign :
				if (!lhs.isLvalue) {
					return getError(lhs, "Expected an lvalue");
				}
				
				auto c = lhs.type.getCanonical();
				if (c.kind == TypeKind.Pointer) {
					lhs = getLvalue(lhs);
					
					// FIXME: check that rhs is an integer.
					if (op == SubAssign) {
						rhs = new UnaryExpression(rhs.location, rhs.type, UnaryOp.Minus, rhs);
					}
					
					auto i = new IndexExpression(e.location, c.element, lhs, rhs);
					auto v = new UnaryExpression(e.location, lhs.type, UnaryOp.AddressOf, i);
					return new BinaryExpression(e.location, lhs.type, Assign, lhs, v);
				}
				
				goto case;
			
			case MulAssign :
			case DivAssign :
			case ModAssign :
			case PowAssign :
				type = lhs.type;
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				break;
			
			case Concat :
				type = lhs.type;
				if (type.getCanonical().kind != TypeKind.Slice) {
					return getError(lhs, "Expected a slice");
				}
				
				rhs = buildImplicitCast(
					pass,
					rhs.location,
					(rhs.type.getCanonical().kind == TypeKind.Slice)
						? type
						: type.element,
					rhs,
				);
				
				return callOverloadSet(
					e.location,
					pass.object.getArrayConcat(),
					[lhs, rhs],
				);
			
			case ConcatAssign :
				assert(0, "~ and ~= not implemented.");
			
			case LogicalOr :
			case LogicalAnd :
				type = Type.get(BuiltinType.Bool);
				
				lhs = buildExplicitCast(pass, lhs.location, type, lhs);
				rhs = buildExplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case LogicalOrAssign :
			case LogicalAndAssign :
				assert(0, "||= and &&= Not implemented.");
			
			case BitwiseOr :
			case BitwiseAnd :
			case BitwiseXor :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type, rhs.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case BitwiseOrAssign :
			case BitwiseAndAssign :
			case BitwiseXorAssign :
				type = lhs.type;
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				break;
			
			case Equal :
			case NotEqual :
			case Identical :
			case NotIdentical :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type, rhs.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				type = Type.get(BuiltinType.Bool);
				break;
			
			case In :
			case NotIn :
				assert(0, "in and !in are not implemented.");
			
			case SignedRightShift :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type, rhs.type);
				
				auto bt = type.builtin;
				if (!isIntegral(bt) || !isSigned(bt)) {
					op = UnsignedRightShift;
				}
				
				goto HandleShift;
			
			case UnsignedRightShift :
			case LeftShift :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type, rhs.type);
			
			HandleShift:
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case SignedRightShiftAssign :
			case UnsignedRightShiftAssign :
			case LeftShiftAssign :
				assert(0,"<<, >> and >>> are not implemented.");
			
			case Greater :
			case GreaterEqual :
			case Less :
			case LessEqual :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type, rhs.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				type = Type.get(BuiltinType.Bool);
				break;
			
			case LessGreater :
			case LessEqualGreater :
			case UnorderedLess :
			case UnorderedLessEqual :
			case UnorderedGreater :
			case UnorderedGreaterEqual :
			case Unordered :
			case UnorderedEqual :
				assert(0, "Unorderd comparisons are not implemented.");
		}
		
		return build!BinaryExpression(e.location, type, op, lhs, rhs);
	}

	Expression visit(AstTernaryExpression e) {
		auto condition = buildExplicitCast(pass, e.condition.location, Type.get(BuiltinType.Bool), visit(e.condition));
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		
		import d.semantic.typepromotion;
		auto t = getPromotedType(pass, e.location, lhs.type, rhs.type);
		
		lhs = buildExplicitCast(pass, lhs.location, t, lhs);
		rhs = buildExplicitCast(pass, rhs.location, t, rhs);
		
		return build!TernaryExpression(e.location, t, condition, lhs, rhs);
	}

	private Expression handleAddressOf(Expression expr) {
		// For fucked up reasons, &funcname is a special case.
		if (auto se = cast(FunctionExpression) expr) {
			return expr;
		} else if (auto pe = cast(PolysemousExpression) expr) {
			import std.algorithm, std.array;
			pe.expressions = pe.expressions.map!(e => handleAddressOf(e)).array();
			return pe;
		}
		
		return build!UnaryExpression(expr.location, expr.type.getPointer(), UnaryOp.AddressOf, expr);
	}
	
	Expression visit(AstUnaryExpression e) {
		auto expr = visit(e.expr);
		auto op = e.op;
		
		Type type;
		final switch(op) with(UnaryOp) {
			case AddressOf :
				return handleAddressOf(expr);
				// It could have been so simple :(
				/+
				type = expr.type.getPointer();
				break;
				+/
			
			case Dereference :
				auto c = expr.type.getCanonical();
				if (c.kind == TypeKind.Pointer) {
					type = c.element;
					break;
				}
				
				return getError(expr, e.location, "Only pointers can be dereferenced");
			
			case PreInc :
			case PreDec :
			case PostInc :
			case PostDec :
				// FIXME: check that type is integer or pointer.
				type = expr.type;
				break;
			
			case Plus :
			case Minus :
			case Complement :
				// FIXME: check that type is integer.
				type = expr.type;
				break;
			
			case Not :
				type = Type.get(BuiltinType.Bool);
				expr = buildExplicitCast(pass, expr.location, type, expr);
				break;
		}
		
		return build!UnaryExpression(e.location, type, op, expr);
	}
	
	Expression visit(AstCastExpression e) {
		import d.semantic.type;
		return buildExplicitCast(pass, e.location, TypeVisitor(pass).visit(e.type), visit(e.expr));
	}
	
	Expression buildArgument(Expression arg, ParamType pt) {
		if (pt.isRef && !canConvert(arg.type.qualifier, pt.qualifier)) {
			return getError(arg, "Can't pass argument by ref");
		}
		
		arg = buildImplicitCast(pass, arg.location, pt.getType(), arg);
		
		// Test if we can pass by ref.
		if (pt.isRef && !arg.isLvalue) {
			return getError(arg, "Argument isn't a lvalue");
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
		final switch(flavor) with(CastKind) {
			case Invalid :
				return MatchLevel.Not;
			
			case IntToPtr :
			case PtrToInt :
			case Down :
			case IntToBool :
			case Trunc :
				assert(0, "Not an implicit cast !");
			
			case SPad :
			case UPad :
			case Bit :
				return MatchLevel.TypeConvert;
			
			case Qual :
				return MatchLevel.QualifierConvert;
			
			case Exact :
				return MatchLevel.Exact;
		}
	}
	
	// XXX: dedup with IdentifierVisitor
	Expression getFrom(Location location, Function f) {
		scheduler.require(f, Step.Signed);
		
		assert(!f.hasThis || !f.hasContext, "this + context not implemented");
		
		Expression e;
		if (f.hasThis) {
			auto ctx = buildImplicitCast(
				pass,
				location,
				f.type.parameters[0].getType(),
				new ThisExpression(location, thisType.getType()),
			);
			
			e = new MethodExpression(location, ctx, f);
		} else if (f.hasContext) {
			import d.semantic.closure;
			e = new MethodExpression(location, new ContextExpression(location, ContextFinder(pass).visit(f)), f);
		} else {
			e = new FunctionExpression(location, f);
		}
		
		assert(e);
		
		// If this is not a property, things are straigforward.
		if (!f.isProperty) {
			return e;
		}
		
		switch(f.params.length) {
			case 0:
				return new CallExpression(location, f.type.returnType.getType(), e, []);
			
			case 1:
				assert(0, "setter not supported)");
			
			default:
				assert(0, "Invalid argument count for property " ~ f.name.toString(context));
		}
	}
	
	Expression visit(AstCallExpression c) {
		// TODO: check if we are in a constructor.
		if (cast(ThisExpression) c.callee) {
			import d.ast.identifier, d.context.name;
			auto call = visit(new IdentifierCallExpression(
				c.location,
				new ExpressionDotIdentifier(c.location, BuiltinName!"__ctor", c.callee),
				c.args,
			));
			
			if (thisType.isFinal) {
				return call;
			}
			
			return build!BinaryExpression(c.location, call.type, BinaryOp.Assign, new ThisExpression(c.location, call.type), call);
		}
		
		import std.algorithm, std.array;
		auto callee = visit(c.callee);
		auto args = c.args.map!(a => visit(a)).array();
		
		return handleCall(c.location, callee, args);
	}
	
	Expression visit(IdentifierCallExpression c) {
		import std.algorithm, std.array;
		auto args = c.args.map!(a => visit(a)).array();
		
		// XXX: Why are doing this here ? Shouldn't this be done in the identifier module ?
		Expression postProcess(T)(T identified) {
			static if (is(T : Expression)) {
				return handleCall(c.location, identified, args);
			} else {
				static if (is(T : Symbol)) {
					if (auto s = cast(OverloadSet) identified) {
						return callOverloadSet(c.location, s, args);
					} else if (auto t = cast(Template) identified) {
						auto callee = handleIFTI(c.location, t, args);
						return callCallable(c.location, callee, args);
					}
				} else static if (is(T : Type)) {
					auto t = identified.getCanonical();
					if (t.kind == TypeKind.Struct) {
						auto callee = handleCtor(c.location, c.callee.location, t, args);
						return callCallable(c.location, callee, args);
					}
				}
				
				return getError(identified, c.location, c.callee.name.toString(pass.context) ~ " isn't callable");
			}
		}
		
		import d.ast.identifier;
		if (auto tidi = cast(TemplateInstanciationDotIdentifier) c.callee) {
			// XXX: For some reason this need to be passed a lambda.
			return TemplateSymbolResolver!(i => postProcess(i))(pass).resolve(tidi, args);
		}
		
		// XXX: For some reason this need to be passed a lambda.
		return SymbolResolver!((i => postProcess(i)))(pass).visit(c.callee);
	}
	
	// XXX: factorize with NewExpression
	private Expression handleCtor(Location location, Location calleeLoc, Type type, Expression[] args) in {
		assert(type.kind == TypeKind.Struct);
	} body {
		import d.semantic.defaultinitializer, d.context.name;
		auto di = InstanceBuilder(pass, calleeLoc).visit(type);
		return AliasResolver!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if (is(T : Symbol)) {
				if (auto f = cast(Function) identified) {
					pass.scheduler.require(f, Step.Signed);
					return new MethodExpression(calleeLoc, di, f);
				} else if (auto s = cast(OverloadSet) identified) {
					import std.algorithm, std.array;
					return chooseOverload(location, s.set.map!(delegate Expression(s) {
						if (auto f = cast(Function) s) {
							pass.scheduler.require(f, Step.Signed);
							return new MethodExpression(calleeLoc, di, f);
						}
						
						assert(0, "not a constructor");
					}).array(), args);
				}
			}
			
			return getError(identified, location, type.dstruct.name.toString(pass.context) ~ " isn't callable");
		})(pass).resolveInSymbol(location, type.dstruct, BuiltinName!"__ctor");
	}
	
	private Expression handleIFTI(Location location, Template t, Expression[] args) {
		import d.semantic.dtemplate;
		TemplateArgument[] targs;
		targs.length = t.parameters.length;
		
		auto i = TemplateInstancier(pass).instanciate(location, t, [], args);
		scheduler.require(i);
		
		return SymbolResolver!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return identified;
			} else {
				return getError(identified, location, t.name.toString(pass.context) ~ " isn't callable");
			}
		})(pass).resolveInSymbol(location, i, t.name);
	}
	
	private Expression callOverloadSet(Location location, OverloadSet s, Expression[] args) {
		import std.algorithm, std.array;
		return callCallable(location, chooseOverload(location, s.set.map!((s) {
			if (auto f = cast(Function) s) {
				return getFrom(location, f);
			} else if (auto t = cast(Template) s) {
				return handleIFTI(location, t, args);
			}
			
			throw new CompileException(s.location, typeid(s).toString() ~ " is not supported in overload set");
		}).array(), args), args);
	}
	
	private static bool checkArgumentCount(bool isVariadic, size_t argCount, size_t paramCount) {
		return isVariadic
			? argCount >= paramCount
			: argCount == paramCount;
	}
	
	private Expression chooseOverload(Location location, Expression[] candidates, Expression[] args) {
		import std.algorithm, std.range;
		auto cds = candidates.map!(e => findCallable(location, e, args)).filter!((e) {
			auto t = e.type.getCanonical();
			if (t.kind == TypeKind.Function) {
				auto ft = t.asFunctionType();
				return checkArgumentCount(ft.isVariadic, args.length, ft.parameters.length);
			}
			
			assert(0, e.type.toString(pass.context) ~ " is not a function type");
		});
		
		auto level = MatchLevel.Not;
		Expression match;
		CandidateLoop: foreach(candidate; cds) {
			auto t = candidate.type.getCanonical();
			assert(t.kind == TypeKind.Function, "We should have filtered function at this point.");
			
			auto candidateLevel = MatchLevel.Exact;
			foreach(arg, param; lockstep(args, t.asFunctionType().parameters)) {
				auto argLevel = matchArgument(arg, param);
				
				// If we don't match high enough.
				if (argLevel < level) {
					continue CandidateLoop;
				}
				
				final switch(argLevel) with(MatchLevel) {
					case Not :
						// This function don't match, go to next one.
						continue CandidateLoop;
					
					case TypeConvert :
					case QualifierConvert :
						candidateLevel = min(candidateLevel, argLevel);
						continue;
					
					case Exact :
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
				assert(mt.kind == TypeKind.Function, "We should have filtered function at this point.");
				
				bool candidateFail;
				bool matchFail;
				foreach(param, matchParam; lockstep(t.asFunctionType().parameters, mt.asFunctionType().parameters)) {
					if (matchArgument(param, matchParam) == MatchLevel.Not) {
						candidateFail = true;
					}
					
					if (matchArgument(matchParam, param) == MatchLevel.Not) {
						matchFail = true;
					}
				}
				
				if (matchFail == candidateFail) {
					return getError(candidate, location, "ambiguous function call.");
				}
				
				if (matchFail) {
					match = candidate;
				}
			}
		}
		
		if (!match) {
			return new CompileError(location, "No candidate for function call").expression;
		}
		
		return match;
	}
	
	private Expression findCallable(Location location, Expression callee, Expression[] args) {
		if (auto asPolysemous = cast(PolysemousExpression) callee) {
			return chooseOverload(location, asPolysemous.expressions, args);
		}
		
		auto type = callee.type.getCanonical();
		if (type.kind == TypeKind.Function) {
			return callee;
		}
		
		import std.algorithm, std.array;
		import d.semantic.aliasthis;
		auto results = AliasThisResolver!((identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return findCallable(location, identified, args);
			} else {
				return cast(Expression) null;
			}
		})(pass).resolve(callee).filter!(e => e !is null && typeid(e) !is typeid(ErrorExpression)).array();
		
		if (results.length == 1) {
			return results[0];
		}
		
		return getError(callee, location, "You must call function or delegates, not " ~ callee.type.toString(context));
	}
	
	private Expression handleCall(Location location, Expression callee, Expression[] args) {
		return callCallable(location, findCallable(location, callee, args), args);
	}
	
	// XXX: This assume that calable is the right one, but not all call sites do the check.
	private Expression callCallable(Location location, Expression callee, Expression[] args) in {
		assert(callee.type.getCanonical().kind == TypeKind.Function);
	} body {
		auto f = callee.type.getCanonical().asFunctionType();
		
		auto paramTypes = f.parameters;
		auto returnType = f.returnType;
		
		import std.range;
		assert(checkArgumentCount(f.isVariadic, args.length, paramTypes.length), "Invalid argument count");
		foreach(ref arg, pt; lockstep(args, paramTypes)) {
			arg = buildArgument(arg, pt);
		}
		
		return build!CallExpression(location, returnType.getType(), callee, args);
	}
	
	// XXX: factorize with handleCtor
	Expression visit(AstNewExpression e) {
		import std.algorithm, std.array;
		auto args = e.args.map!(a => visit(a)).array();
		
		import d.semantic.type;
		auto type = TypeVisitor(pass).visit(e.type);
		
		import d.semantic.defaultinitializer;
		auto di = NewBuilder(pass, e.location).visit(type);
		
		import d.context.name;
		auto ctor = AliasResolver!(delegate FunctionExpression(identified) {
			static if (is(typeof(identified) : Symbol)) {
				if (auto f = cast(Function) identified) {
					pass.scheduler.require(f, Step.Signed);
					return new FunctionExpression(e.location, f);
				} else if (auto s = cast(OverloadSet) identified) {
					auto m = chooseOverload(e.location, s.set.map!(delegate Expression(s) {
						if (auto f = cast(Function) s) {
							pass.scheduler.require(f, Step.Signed);
							return new MethodExpression(e.location, di, f);
						}
						
						assert(0, "not a constructor");
					}).array(), args);
					
					// XXX: find a clean way to achieve this.
					return new FunctionExpression(e.location, (cast(MethodExpression) m).method);
				}
			}
			
			assert(0, "Gimme some construtor !");
		})(pass).resolveInType(e.location, type, BuiltinName!"__ctor");
		
		auto funType = ctor.fun.type;
		
		// First parameter is compiler magic.
		auto parameters = funType.parameters[1 .. $];
		
		import std.range;
		assert(args.length >= parameters.length);
		foreach(ref arg, pt; lockstep(args, parameters)) {
			arg = buildArgument(arg, pt);
		}
		
		if (type.getCanonical().kind != TypeKind.Class) {
			type = type.getPointer();
		}
		
		return build!NewExpression(e.location, type, di, ctor, args);
	}
	
	Expression visit(ThisExpression e) {
		e.type = thisType.getType();
		return e;
	}
	
	Expression getIndex(Location location, Expression indexed, Expression index) {
		auto t = indexed.type.getCanonical();
		if (!t.hasElement) {
			return getError(indexed, location, "Can't index " ~ indexed.type.toString(context));
		}
		
		index = buildImplicitCast(pass, location, pass.object.getSizeT().type, index);
		return build!IndexExpression(location, t.element, indexed, index);
	}
	
	Expression visit(AstIndexExpression e) {
		auto indexed = visit(e.indexed);
		
		import std.algorithm, std.array;
		auto arguments = e.arguments.map!(e => visit(e)).array();
		assert(arguments.length == 1, "Multiple argument index are not supported");
		
		return getIndex(e.location, indexed, arguments[0]);
	}
	
	Expression visit(AstSliceExpression e) {
		// TODO: check if it is valid.
		auto sliced = visit(e.sliced);
		
		auto t = sliced.type.getCanonical();
		if (!t.hasElement) {
			return getError(sliced, e.location, "Can't slice " ~ t.toString(context));
		}
		
		assert(e.first.length == 1 && e.second.length == 1);
		
		auto first = visit(e.first[0]);
		auto second = visit(e.second[0]);
		
		return build!SliceExpression(e.location, t.element.getSlice(), sliced, first, second);
	}
	
	Expression visit(AstAssertExpression e) {
		auto c = visit(e.condition);
		c = buildExplicitCast(pass, c.location, Type.get(BuiltinType.Bool), c);
		
		Expression msg;
		if (e.message) {
			msg = visit(e.message);
			
			// TODO: ensure that msg is a string.
		}
		
		return build!AssertExpression(e.location, Type.get(BuiltinType.Void), c, msg);
	}
	
	private Expression handleTypeid(Location location, Expression e) {
		auto c = e.type.getCanonical();
		if (c.kind == TypeKind.Class) {
			auto classInfo = pass.object.getClassInfo();
			return new DynamicTypeidExpression(location, Type.get(classInfo), e);
		}
		
		return getTypeInfo(location, e.type);
	}
	
	auto getTypeInfo(Location location, Type t) {
		t = t.getCanonical();
		if (t.kind == TypeKind.Class) {
			return getClassInfo(location, t.dclass);
		}
		
		alias StaticTypeidExpression = d.ir.expression.StaticTypeidExpression;
		return new StaticTypeidExpression(location, Type.get(pass.object.getTypeInfo()), t);
	}
	
	auto getClassInfo(Location location, Class c) {
		alias StaticTypeidExpression = d.ir.expression.StaticTypeidExpression;
		return new StaticTypeidExpression(location, Type.get(pass.object.getClassInfo()), Type.get(c));
	}
	
	Expression visit(AstTypeidExpression e) {
		return handleTypeid(e.location, visit(e.argument));
	}
	
	Expression visit(AstStaticTypeidExpression e) {
		import d.semantic.type;
		return getTypeInfo(e.location, TypeVisitor(pass).visit(e.argument));
	}
	
	Expression visit(IdentifierTypeidExpression e) {
		return SymbolResolver!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if (is(T : Type)) {
				return getTypeInfo(e.location, identified);
			} else static if (is(T : Expression)) {
				return handleTypeid(e.location, identified);
			} else {
				return getError(identified, e.location, "Can't get typeid of " ~ e.argument.name.toString(pass.context));
			}
		})(pass).visit(e.argument);
	}
	
	Expression visit(IdentifierExpression e) {
		return SymbolResolver!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return identified;
			} else {
				static if (is(T : Symbol)) {
					if (auto s = cast(OverloadSet) identified) {
						return buildPolysemous(e.location, s);
					}
				}
				
				return getError(identified, e.location, e.identifier.name.toString(pass.context) ~ " isn't an expression");
			}
		})(pass).visit(e.identifier);
	}
	
	private Expression buildPolysemous(Location location, OverloadSet s) {
		auto spp = SymbolPostProcessor!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if (is(T : Expression)) {
				return identified;
			} else static if (is(T : Type)) {
				assert(0, "Type can't be overloaded");
			} else {
				// TODO: handle templates.
				throw new CompileException(identified.location, typeid(identified).toString() ~ " is not supported in overload set");
			}
		})(pass, location);
		
		import std.algorithm, std.array;
		auto exprs = s.set.map!(s => spp.visit(s)).array();
		return new PolysemousExpression(location, exprs);
	}
	
	import d.ast.declaration, d.ast.statement;
	private auto handleDgs(Location location, string prefix, ParamDecl[] params, bool isVariadic, AstBlockStatement fbody) {
		// FIXME: can still collide with mixins, but that should rare enough for now.
		import std.conv;
		auto offset = location.getFullLocation(context).getStartOffset();
		auto name = context.getName(prefix ~ offset.to!string());
		
		auto d = new FunctionDeclaration(
			location,
			defaultStorageClass,
			AstType.getAuto().getParamType(false, false),
			name,
			params,
			isVariadic,
			fbody,
		);
		
		auto f = new Function(location, currentScope, FunctionType.init, name, [], null);
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
			new AstBlockStatement(v.location, [new AstReturnStatement(v.location, v)]),
		);
	}
}
