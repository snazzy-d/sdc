module d.semantic.expression;

import d.semantic.caster;
import d.semantic.identifier;
import d.semantic.semantic;

import d.ast.base;
import d.ast.expression;
import d.ast.type;

import d.ir.dscope;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.exception;

import std.algorithm;
import std.array;
import std.range;

alias TernaryExpression = d.ir.expression.TernaryExpression;
alias BinaryExpression = d.ir.expression.BinaryExpression;
alias CallExpression = d.ir.expression.CallExpression;
alias NewExpression = d.ir.expression.NewExpression;
alias IndexExpression = d.ir.expression.IndexExpression;
alias SliceExpression = d.ir.expression.SliceExpression;
alias AssertExpression = d.ir.expression.AssertExpression;

alias PointerType = d.ir.type.PointerType;
alias SliceType = d.ir.type.SliceType;
alias ArrayType = d.ir.type.ArrayType;
alias FunctionType = d.ir.type.FunctionType;

struct ExpressionVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Expression visit(AstExpression e) {
		return this.dispatch!((e) {
			return pass.raiseCondition!Expression(e.location, typeid(e).toString() ~ " is not supported");
		})(e);
	}
	
	Expression visit(ParenExpression e) {
		return visit(e.expr);
	}
	
	Expression visit(BooleanLiteral e) {
		return e;
	}
	
	Expression visit(IntegerLiteral!true e) {
		return e;
	}
	
	Expression visit(IntegerLiteral!false e) {
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
	
	private Expression getRvalue(Expression value) {
		auto v = new Variable(value.location, value.type, BuiltinName!"", value);
		v.storage = Storage.Enum;
		v.step = Step.Processed;
		
		return new VariableExpression(value.location, v);
	}
	
	private Expression getLvalue(Expression value) {
		auto pt = QualType(new PointerType(value.type));
		auto ptr = new UnaryExpression(value.location, pt, UnaryOp.AddressOf, value);
		auto v = getRvalue(ptr);
		
		return new UnaryExpression(value.location, value.type, UnaryOp.Dereference, v);
	}
	
	Expression visit(AstBinaryExpression e) {
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		auto op = e.op;
		
		QualType type;
		final switch(op) with(BinaryOp) {
			case Comma:
				type = rhs.type;
				break;
			
			case Assign :
				type = lhs.type;
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				break;
			
			case Add :
			case Sub :
				if(auto pt = cast(PointerType) peelAlias(lhs.type).type) {
					// FIXME: check that rhs is an integer.
					if(op == Sub) {
						rhs = new UnaryExpression(rhs.location, rhs.type, UnaryOp.Minus, rhs);
					}
					
					auto i = new IndexExpression(e.location, pt.pointed, lhs, [rhs]);
					return new UnaryExpression(e.location, lhs.type, UnaryOp.AddressOf, i);
				}
				
				goto case;
			
			case Mul :
			case Div :
			case Mod :
			case Pow :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type.type, rhs.type.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case AddAssign :
			case SubAssign :
				if(auto pt = cast(PointerType) peelAlias(lhs.type).type) {
					lhs = getLvalue(lhs);
					
					// FIXME: check that rhs is an integer.
					if(op == SubAssign) {
						rhs = new UnaryExpression(rhs.location, rhs.type, UnaryOp.Minus, rhs);
					}
					
					auto i = new IndexExpression(e.location, pt.pointed, lhs, [rhs]);
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
			case ConcatAssign :
				assert(0, "~,~= not implemented.");
			
			case LogicalOr :
			case LogicalAnd :
				type = getBuiltin(TypeKind.Bool);
				
				lhs = buildExplicitCast(pass, lhs.location, type, lhs);
				rhs = buildExplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case LogicalOrAssign :
			case LogicalAndAssign :
				assert(0, "||=, &&= Not implemented.");
			
			case BitwiseOr :
			case BitwiseAnd :
			case BitwiseXor :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type.type, rhs.type.type);
				
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
				type = getPromotedType(pass, e.location, lhs.type.type, rhs.type.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				type = getBuiltin(TypeKind.Bool);
				break;
			
			case In :
			case NotIn :
				assert(0, "in and !in are not implemented.");
			
			case LeftShift :
			case SignedRightShift :
			case UnsignedRightShift :
				type = lhs.type;
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				break;
			
			case LeftShiftAssign :
			case SignedRightShiftAssign :
			case UnsignedRightShiftAssign :
				assert(0,"<<, >> and >>> are not implemented.");
			
			case Greater :
			case GreaterEqual :
			case Less :
			case LessEqual :
				import d.semantic.typepromotion;
				type = getPromotedType(pass, e.location, lhs.type.type, rhs.type.type);
				
				lhs = buildImplicitCast(pass, lhs.location, type, lhs);
				rhs = buildImplicitCast(pass, rhs.location, type, rhs);
				
				type = getBuiltin(TypeKind.Bool);
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
		
		return new BinaryExpression(e.location, type, op, lhs, rhs);
	}

	Expression visit(AstTernaryExpression e) {
		auto condition = buildExplicitCast(pass, e.condition.location, getBuiltin(TypeKind.Bool), visit(e.condition));
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		
		import d.semantic.typepromotion;
		auto t = getPromotedType(pass, e.location, lhs.type.type, rhs.type.type);
		
		lhs = buildExplicitCast(pass, lhs.location, t, lhs);
		rhs = buildExplicitCast(pass, rhs.location, t, rhs);
		
		return new TernaryExpression(e.location, t, condition, lhs, rhs);
	}

	private Expression handleAddressOf(Expression expr) {
		// For fucked up reasons, &funcname is a special case.
		if(auto se = cast(FunctionExpression) expr) {
			return expr;
		} else if(auto pe = cast(PolysemousExpression) expr) {
			pe.expressions = pe.expressions.map!(e => handleAddressOf(e)).array();
			return pe;
		}
		
		return new UnaryExpression(expr.location, QualType(new PointerType(expr.type)), UnaryOp.AddressOf, expr);
	}
	
	Expression visit(AstUnaryExpression e) {
		auto expr = visit(e.expr);
		auto op = e.op;
		
		QualType type;
		final switch(op) with(UnaryOp) {
			case AddressOf :
				return handleAddressOf(expr);
				// It could have been so simple :(
				/+
				type = QualType(new PointerType(expr.type));
				break;
				+/
			
			case Dereference :
				if(auto pt = cast(PointerType) peelAlias(expr.type).type) {
					type = pt.pointed;
					break;
				}
				
				return pass.raiseCondition!Expression(e.location, "Only pointers can be dereferenced, not " ~ expr.type.toString(context));
			
			case PreInc :
			case PreDec :
			case PostInc :
			case PostDec :
				if(auto pt = cast(PointerType) peelAlias(expr.type).type) {
					expr = getLvalue(expr);
					
					Expression n = new IntegerLiteral!true(e.location, (op == PreInc || op == PostInc)? 1 : -1, TypeKind.Ulong);
					auto i = new IndexExpression(e.location, pt.pointed, expr, [n]);
					auto v = new UnaryExpression(e.location, expr.type, AddressOf, i);
					auto r = new BinaryExpression(e.location, expr.type, BinaryOp.Assign, expr, v);
					
					if(op == PreInc || op == PreDec) {
						return r;
					}
					
					auto l = getRvalue(expr);
					r = new BinaryExpression(e.location, expr.type, BinaryOp.Comma, l, r);
					return new BinaryExpression(e.location, expr.type, BinaryOp.Comma, r, l);
				}
				
				type = expr.type;
				break;
			
			case Plus :
			case Minus :
				// FIXME: check that type is integer.
				type = expr.type;
				break;
			
			case Not :
				type = getBuiltin(TypeKind.Bool);
				expr = buildExplicitCast(pass, expr.location, type, expr);
				break;
			
			case Complement :
				assert(0, "unary ~ not implemented.");
		}
		
		return new UnaryExpression(e.location, type, op, expr);
	}
	
	Expression visit(AstCastExpression e) {
		import d.semantic.type;
		auto tv = TypeVisitor(pass);
		return buildExplicitCast(pass, e.location, tv.visit(e.type), visit(e.expr));
	}
	
	Expression buildArgument(Expression arg, ParamType pt) {
		if(pt.isRef && !canConvert(arg.type.qualifier, pt.qualifier)) {
			return pass.raiseCondition!Expression(arg.location, "Can't pass argument by ref.");
		}
		
		arg = buildImplicitCast(pass, arg.location, QualType(pt.type, pt.qualifier), arg);
		
		// test if we can pass by ref.
		if(pt.isRef && !arg.isLvalue) {
			import std.stdio;
			writeln(arg.toString(context), " is an lvalue ?\t", arg.isLvalue);
			
			return pass.raiseCondition!Expression(arg.location, "Argument isn't a lvalue.");
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
		if(param.isRef && !canConvert(arg.type.qualifier, param.qualifier)) {
			return MatchLevel.Not;
		}
		
		auto flavor = implicitCastFrom(pass, arg.type, QualType(param.type, param.qualifier));
		
		// test if we can pass by ref.
		if(param.isRef && !(flavor >= CastKind.Bit && arg.isLvalue)) {
			return MatchLevel.Not;
		}
		
		return matchLevel(flavor);
	}
	
	// TODO: deduplicate.
	private auto matchArgument(ParamType type, ParamType param) {
		if(param.isRef && !canConvert(type.qualifier, param.qualifier)) {
			return MatchLevel.Not;
		}
		
		auto flavor = implicitCastFrom(pass, QualType(type.type, type.qualifier), QualType(param.type, param.qualifier));
		
		// test if we can pass by ref.
		if(param.isRef && !(flavor >= CastKind.Bit && type.isRef)) {
			return MatchLevel.Not;
		}
		
		return matchLevel(flavor);
	}
	
	private auto matchLevel(CastKind flavor) {
		final switch(flavor) with(CastKind) {
			case Invalid :
				return MatchLevel.Not;
			
			case Down :
			case IntegralToBool :
			case Trunc :
				assert(0, "Not an implicit cast !");
			
			case Pad :
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
			auto type = f.type.paramTypes[0];
			auto ctx = buildImplicitCast(pass, location, QualType(type.type, type.qualifier), new ThisExpression(location, QualType(thisType.type)));
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
		
		switch(f.params.length - f.hasContext - f.hasThis) {
			case 0:
				return new CallExpression(location, QualType(f.type.returnType.type, f.type.returnType.qualifier), e, []);
			
			case 1:
				assert(0, "setter not supported)");
			
			default:
				assert(0, "Invalid argument count for property " ~ f.name.toString(context));
		}
	}
	
	Expression visit(AstCallExpression c) {
		// TODO: check if we are in a constructor.
		if(cast(ThisExpression) c.callee) {
			import d.ast.identifier;
			auto call = visit(new IdentifierCallExpression(c.location, new ExpressionDotIdentifier(c.location, BuiltinName!"__ctor", c.callee), c.args));
			
			if(thisType.isFinal) {
				return call;
			}
			
			return new BinaryExpression(c.location, call.type, BinaryOp.Assign, new ThisExpression(c.location, call.type), call);
		}
		
		auto callee = visit(c.callee);
		auto args = c.args.map!(a => visit(a)).array();
		
		return handleCall(c.location, callee, args);
	}
	
	Expression visit(IdentifierCallExpression c) {
		auto args = c.args.map!(a => visit(a)).array();
		
		// XXX: Why are doing this here ? Shouldn't this be done in the identifier module ?
		Expression postProcess(T)(T identified) {
			static if(is(T : Expression)) {
				return handleCall(c.location, identified, args);
			} else {
				static if(is(T : Symbol)) {
					if(auto s = cast(OverloadSet) identified) {
						return callOverloadSet(c.location, s, args);
					} else if(auto t = cast(Template) identified) {
						auto callee = handleIFTI(c.location, t, args);
						return callCallable(c.location, callee, args);
					}
				} else static if(is(T : QualType)) {
					if (auto t = cast(StructType) identified.type) {
						auto callee = handleCtor(c.location, c.callee.location, t, args);
						return callCallable(c.location, callee, args);
					}
				}
				
				return pass.raiseCondition!Expression(c.location, c.callee.name.toString(pass.context) ~ " isn't callable.");
			}
		}
		
		import d.ast.identifier;
		if(auto tidi = cast(TemplateInstanciationDotIdentifier) c.callee) {
			// XXX: For some reason this need to be passed a lambda.
			return TemplateDotIdentifierResolver!(i => postProcess(i))(pass).resolve(tidi, args);
		}
		
		// XXX: For some reason this need to be passed a lambda.
		return SymbolResolver!((i => postProcess(i)))(pass).visit(c.callee);
	}
	
	// XXX: factorize with NewExpression
	private Expression handleCtor(Location location, Location calleeLoc, StructType type, Expression[] args) {
		import d.semantic.defaultinitializer;
		auto di = InstanceBuilder(pass, calleeLoc).visit(QualType(type));
		return AliasResolver!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if(is(T : Symbol)) {
				if (auto f = cast(Function) identified) {
					pass.scheduler.require(f, Step.Signed);
					return new MethodExpression(calleeLoc, di, f);
				} else if(auto s = cast(OverloadSet) identified) {
					return chooseOverload(location, s.set.map!(delegate Expression(s) {
						if (auto f = cast(Function) s) {
							pass.scheduler.require(f, Step.Signed);
							return new MethodExpression(calleeLoc, di, f);
						}
						
						assert(0, "not a constructor");
					}).array(), args);
				}
			}
			
			return pass.raiseCondition!Expression(location, type.dstruct.name.toString(pass.context) ~ " isn't callable.");
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
			static if(is(T : Expression)) {
				return identified;
			} else {
				return pass.raiseCondition!Expression(location, t.name.toString(pass.context) ~ " isn't callable.");
			}
		})(pass).resolveInSymbol(location, i, t.name);
	}
	
	private Expression callOverloadSet(Location location, OverloadSet s, Expression[] args) {
		return callCallable(location, chooseOverload(location, s.set.map!((s) {
			if(auto f = cast(Function) s) {
				return getFrom(location, f);
			} else if(auto t = cast(Template) s) {
				return handleIFTI(location, t, args);
			}
			
			throw new CompileException(s.location, typeid(s).toString() ~ " is not supported in overload set");
		}).array(), args), args);
	}
	
	private Expression chooseOverload(Location location, Expression[] candidates, Expression[] args) {
		auto cds = candidates.map!(e => findCallable(location, e, args)).filter!((e) {
			if(auto asFunType = cast(FunctionType) peelAlias(e.type).type) {
				if(asFunType.isVariadic) {
					return args.length >= asFunType.paramTypes.length;
				} else {
					return args.length == asFunType.paramTypes.length;
				}
			}
			
			assert(0, e.type.toString(pass.context) ~ " is not a function type");
		});
		
		auto level = MatchLevel.Not;
		Expression match;
		CandidateLoop: foreach(candidate; cds) {
			auto type = cast(FunctionType) peelAlias(candidate.type).type;
			assert(type, "We should have filtered function at this point.");
			
			auto candidateLevel = MatchLevel.Exact;
			foreach(arg, param; lockstep(args, type.paramTypes)) {
				auto argLevel = matchArgument(arg, param);
				
				// If we don't match high enough.
				if(argLevel < level) {
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
			
			if(candidateLevel > level) {
				level = candidateLevel;
				match = candidate;
			} else if(candidateLevel == level) {
				// Check for specialisation.
				auto matchType = cast(FunctionType) peelAlias(match.type).type;
				assert(matchType, "We should have filtered function at this point.");
				
				bool candidateFail;
				bool matchFail;
				foreach(param, matchParam; lockstep(type.paramTypes, matchType.paramTypes)) {
					if(matchArgument(param, matchParam) == MatchLevel.Not) {
						candidateFail = true;
					}
					
					if(matchArgument(matchParam, param) == MatchLevel.Not) {
						matchFail = true;
					}
				}
				
				if(matchFail == candidateFail) {
					return pass.raiseCondition!Expression(location, "ambiguous function call.");
				}
				
				if(matchFail) {
					match = candidate;
				}
			}
		}
		
		if(!match) {
			return pass.raiseCondition!Expression(location, "No candidate for function call.");
		}
		
		return match;
	}
	
	private Expression findCallable(Location location, Expression callee, Expression[] args) {
		if(auto asPolysemous = cast(PolysemousExpression) callee) {
			return chooseOverload(location, asPolysemous.expressions, args);
		}
		
		auto type = peelAlias(callee.type).type;
		if(auto f = cast(FunctionType) type) {
			return callee;
		}
		
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
		
		return pass.raiseCondition!Expression(location, "You must call function or delegates, not " ~ callee.type.toString(context));
	}
	
	private Expression handleCall(Location location, Expression callee, Expression[] args) {
		return callCallable(location, findCallable(location, callee, args), args);
	}
	
	private Expression callCallable(Location location, Expression callee, Expression[] args) {
		auto f = cast(FunctionType) peelAlias(callee.type).type;
		assert(f, "This method must be used with a callable");
		
		auto paramTypes = f.paramTypes;
		auto returnType = f.returnType;
		
		assert(args.length >= paramTypes.length);
		
		foreach(ref arg, pt; lockstep(args, paramTypes)) {
			arg = buildArgument(arg, pt);
		}
		
		return new CallExpression(location, QualType(returnType.type, returnType.qualifier), callee, args);
	}
	
	// XXX: factorize with handleCtor
	Expression visit(AstNewExpression e) {
		auto args = e.args.map!(a => visit(a)).array();
		
		import d.semantic.type, d.semantic.defaultinitializer;
		auto type = TypeVisitor(pass).visit(e.type);
		auto di = NewBuilder(pass, e.location).visit(type);
		auto ctor = AliasResolver!(delegate FunctionExpression(identified) {
			static if(is(typeof(identified) : Symbol)) {
				if(auto f = cast(Function) identified) {
					pass.scheduler.require(f, Step.Signed);
					return new FunctionExpression(e.location, f);
				} else if(auto s = cast(OverloadSet) identified) {
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
		if(!funType) {
			return pass.raiseCondition!Expression(e.location, "Invalid constructor.");
		}
		
		// First parameter is compiler magic.
		auto paramTypes = funType.paramTypes[1 .. $];
		
		assert(args.length >= paramTypes.length);
		foreach(ref arg, pt; lockstep(args, paramTypes)) {
			arg = buildArgument(arg, pt);
		}
		
		if(typeid({ return peelAlias(type).type; } ()) !is typeid(ClassType)) {
			type = QualType(new PointerType(type));
		}
		
		return new NewExpression(e.location, type, di, ctor, args);
	}
	
	Expression visit(ThisExpression e) {
		e.type = QualType(thisType.type, thisType.qualifier);
		return e;
	}
	
	Expression visit(AstIndexExpression e) {
		auto indexed = visit(e.indexed);
		
		auto qt = peelAlias(indexed.type);
		auto type = qt.type;
		if(auto asSlice = cast(SliceType) type) {
			qt = asSlice.sliced;
		} else if(auto asPointer = cast(PointerType) type) {
			qt = asPointer.pointed;
		} else if(auto asArray = cast(ArrayType) type) {
			qt = asArray.elementType;
		} else {
			return pass.raiseCondition!Expression(e.location, "Can't index " ~ indexed.type.toString(context));
		}
		
		auto arguments = e.arguments.map!(e => visit(e)).array();
		
		return new IndexExpression(e.location, qt, indexed, arguments);
	}
	
	Expression visit(AstSliceExpression e) {
		// TODO: check if it is valid.
		auto sliced = visit(e.sliced);
		
		auto qt = peelAlias(sliced.type);
		auto type = qt.type;
		if(auto asSlice = cast(SliceType) type) {
			qt.type = asSlice.sliced.type;
		} else if(auto asPointer = cast(PointerType) type) {
			qt.type = asPointer.pointed.type;
		} else if(auto asArray = cast(ArrayType) type) {
			qt.type = asArray.elementType.type;
		} else {
			return pass.raiseCondition!Expression(e.location, "Can't slice " ~ sliced.type.toString(context));
		}
		
		auto first = e.first.map!(e => visit(e)).array();
		auto second = e.second.map!(e => visit(e)).array();
		
		return new SliceExpression(e.location, QualType(new SliceType(qt)), sliced, first, second);
	}
	
	Expression visit(AstAssertExpression e) {
		auto c = visit(e.condition);
		c = buildExplicitCast(pass, c.location, getBuiltin(TypeKind.Bool), c);
		
		Expression msg;
		if(e.message) {
			msg = visit(e.message);
			
			// TODO: ensure that msg is a string.
		}
		
		return new AssertExpression(e.location, getBuiltin(TypeKind.Void), c, msg);
	}
	
	private Expression handleTypeid(Location location, Expression e) {
		if(auto c = cast(ClassType) peelAlias(e.type).type) {
			auto classInfo = pass.object.getClassInfo();
			return new DynamicTypeidExpression(location, QualType(new ClassType(classInfo)), e);
		}
		
		return getTypeInfo(location, e.type);
	}
	
	auto getTypeInfo(Location location, QualType t) {
		if(auto ct = cast(ClassType) peelAlias(t).type) {
			return getClassInfo(location, ct);
		}
		
		alias StaticTypeidExpression = d.ir.expression.StaticTypeidExpression;
		return new StaticTypeidExpression(location, QualType(new ClassType(pass.object.getTypeInfo())), t);
	}
	
	auto getClassInfo(Location location, ClassType t) {
		alias StaticTypeidExpression = d.ir.expression.StaticTypeidExpression;
		return new StaticTypeidExpression(location, QualType(new ClassType(pass.object.getClassInfo())), QualType(t));
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
			static if(is(T : QualType)) {
				return getTypeInfo(e.location, identified);
			} else static if(is(T : Expression)) {
				return handleTypeid(e.location, identified);
			} else {
				return pass.raiseCondition!Expression(e.location, "Can't get typeid of " ~ e.argument.name.toString(pass.context) ~ ".");
			}
		})(pass).visit(e.argument);
	}
	
	Expression visit(IdentifierExpression e) {
		return SymbolResolver!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if(is(T : Expression)) {
				return identified;
			} else {
				static if(is(T : Symbol)) {
					if(auto s = cast(OverloadSet) identified) {
						return buildPolysemous(e.location, s);
					}
				}
				
				return pass.raiseCondition!Expression(e.location, e.identifier.name.toString(pass.context) ~ " isn't an expression.");
			}
		})(pass).visit(e.identifier);
	}
	
	private Expression buildPolysemous(Location location, OverloadSet s) {
		auto spp = SymbolPostProcessor!(delegate Expression(identified) {
			alias T = typeof(identified);
			static if(is(T : Expression)) {
				return identified;
			} else static if(is(T : QualType)) {
				assert(0, "Type can't be overloaded");
			} else {
				// TODO: handle templates.
				throw new CompileException(identified.location, typeid(identified).toString() ~ " is not supported in overload set");
			}
		})(pass, location);
		
		auto exprs = s.set.map!(s => spp.visit(s)).array();
		return new PolysemousExpression(location, exprs);
	}
	
	import d.ast.declaration, d.ast.statement;
	private auto handleDgs(Location location, string prefix, ParamDecl[] params, bool isVariadic, AstBlockStatement fbody) {
		// FIXME: can still collide with mixins, but that should rare enough for now.
		import std.conv;
		auto name = context.getName(prefix ~ to!string(location.line) ~ "_" ~ to!string(location.index));
		
		auto d = new FunctionDeclaration(
			location,
			defaultStorageClass,
			ParamAstType(new AutoType(), false),
			name,
			params,
			isVariadic,
			fbody,
		);
		
		auto f = new Function(location, null, name, [], null);
		f.hasContext = true;
		
		import d.semantic.symbol;
		auto sv = SymbolAnalyzer(pass);
		sv.analyze(d, f);
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

