module d.semantic.expression;

import d.semantic.identifiable;
import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.exception;

import std.algorithm;
import std.array;
import std.range;

final class ExpressionVisitor {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	Expression visit(Expression e) out(result) {
		assert(result.type, "type must be resolved for expression.");
	} body {
		return this.dispatch(e);
	}
	
	Expression visit(PolysemousExpression e) {
		e.expressions = e.expressions.map!(e => visit(e)).array();
		
		e.type = new ErrorType(e.location);
		
		return e;
	}
	
	Expression visit(ParenExpression e) {
		return visit(e.expression);
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
	
	Expression visit(StringLiteral e) {
		return e;
	}
	
	Expression visit(CommaExpression e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		e.type = e.rhs.type;
		
		return e;
	}
	
	Expression visit(AssignExpression e) {
		e.lhs = visit(e.lhs);
		e.type = e.lhs.type;
		
		e.rhs = implicitCast(e.rhs.location, e.type, visit(e.rhs));
		
		return e;
	}
	
	private Expression handleArithmeticExpression(string operation)(BinaryExpression!operation e) if(find(["+", "+=", "-", "-="], operation)) {
		enum isOpAssign = operation.length == 2;
		
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		if(auto pointerType = cast(PointerType) e.lhs.type) {
			if(typeid({ return e.rhs.type; }()) !is typeid(IntegerType)) {
				return pass.raiseCondition!Expression(e.rhs.location, "Pointer +/- interger only.");
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
			
			e.lhs = implicitCast(e.lhs.location, e.type, e.lhs);
		}
		
		e.rhs = implicitCast(e.rhs.location, e.type, e.rhs);
		
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
	
	Expression visit(ConcatExpression e) {
		e.lhs = visit(e.lhs);
		
		if(auto sliceType = cast(SliceType) e.lhs.type) {
			auto type = e.type = e.lhs.type;
			e.rhs = implicitCast(e.rhs.location, type, visit(e.rhs));
			
			return e;
		}
		
		return pass.raiseCondition!Expression(e.location, "Concat slice only.");
	}
	
	private auto handleBinaryExpression(string operation)(BinaryExpression!operation e) {
		e.lhs = visit(e.lhs);
		e.rhs = visit(e.rhs);
		
		import std.algorithm;
		static if(find(["&&", "||"], operation)) {
			e.type = new BooleanType(e.location);
			
			e.lhs = explicitCast(e.lhs.location, e.type, e.lhs);
			e.rhs = explicitCast(e.rhs.location, e.type, e.rhs);
		} else static if(find(["==", "!=", ">", ">=", "<", "<="], operation)) {
			auto type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = implicitCast(e.lhs.location, type, e.lhs);
			e.rhs = implicitCast(e.rhs.location, type, e.rhs);
			
			e.type = new BooleanType(e.location);
		} else static if(find(["&", "|", "^", "*", "/", "%"], operation)) {
			e.type = getPromotedType(e.location, e.lhs.type, e.rhs.type);
			
			e.lhs = implicitCast(e.lhs.location, e.type, e.lhs);
			e.rhs = implicitCast(e.rhs.location, e.type, e.rhs);
		} else static if(find([","], operation)) {
			e.type = e.rhs.type;
		} else {
			static assert(0);
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
	
	private Expression handleUnaryExpression(alias fun, UnaryExpression)(UnaryExpression e) {
		e.expression = visit(e.expression);
		
		// Propagate polysemous expressions.
		if(auto asPolysemous = cast(PolysemousExpression) e.expression) {
			auto ret = new PolysemousExpression(e.location, asPolysemous.expressions.map!(delegate Expression(Expression e) {
				return fun(new UnaryExpression(asPolysemous.location, e));
			}).array());
			
			ret.type = new ErrorType(ret.location);
			
			return ret;
		}
		
		return fun(e);
	}
	
	private auto handleIncrementExpression(UnaryExpression)(UnaryExpression e) {
		// DMD don't understand that it has all infos already :(
		static SemanticPass workaround;
		auto oldWA = workaround;
		scope(exit) workaround = oldWA;
		
		return handleUnaryExpression!(function Expression(UnaryExpression e) {
			e.type = e.expression.type;
		
			if(auto pointerType = cast(PointerType) e.expression.type) {
				return e;
			} else if(auto integerType = cast(IntegerType) e.expression.type) {
				return e;
			}
			
			return workaround.raiseCondition!Expression(e.location, "Increment and decrement are performed on integers or pointer types.");
		})(e);
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
		return handleUnaryExpression!((UnaryMinusExpression e) {
			e.type = e.expression.type;
			
			return e;
		})(e);
	}
	
	Expression visit(UnaryPlusExpression e) {
		// DMD don't understand that it has all infos already :(
		static SemanticPass workaround;
		auto oldWA = workaround;
		scope(exit) workaround = oldWA;
		
		return handleUnaryExpression!((UnaryPlusExpression e) {
			if(typeid({ return e.expression.type; }()) !is typeid(IntegerType)) {
				return workaround.raiseCondition!Expression(e.location, "unary plus only apply to integers.");
			}
			
			return e.expression;
		})(e);
	}
	
	Expression visit(NotExpression e) {
		// XXX: Hack around the fact that delegate cannot be passed as parameter here.
		auto ue = handleUnaryExpression!((NotExpression e) {
			e.type = new BooleanType(e.location);
			
			return e;
		})(e);
		
		if(auto ne = cast(NotExpression) ue) {
			ne.expression = pass.explicitCast(ne.location, ne.type, ne.expression);
		}
		
		return ue;
	}
	
	Expression visit(AddressOfExpression e) {
		// FIXME: explode polysemous expression for all unary expression.
		if(typeid({ return e.expression; }()) is typeid(AddressOfExpression)) {
			return pass.raiseCondition!Expression(e.location, "Cannot take the address of an address.");
		}
		
		return handleUnaryExpression!((AddressOfExpression e) {
			// For fucked up reasons, &funcname is a special case.
			if(auto asSym = cast(SymbolExpression) e.expression) {
				if(auto asDecl = cast(FunctionDeclaration) asSym.symbol) {
					return e.expression;
				}
			}
			
			e.type = new PointerType(e.location, e.expression.type);
			
			return e;
		})(e);
	}
	
	Expression visit(DereferenceExpression e) {
		// DMD don't understand that it has all infos already :(
		static SemanticPass workaround;
		auto oldWA = workaround;
		scope(exit) workaround = oldWA;
		
		return handleUnaryExpression!(function Expression(DereferenceExpression e) {
			if(auto pt = cast(PointerType) e.expression.type) {
				e.type = pt.type;
				
				return e;
			}
			
			return workaround.raiseCondition!Expression(e.location, typeid({ return e.expression.type; }()).toString() ~ " is not a pointer type.");
		})(e);
	}
	
	Expression visit(CastExpression e) {
		auto to = pass.visit(e.type);
		return explicitCast(e.location, to, visit(e.expression));
	}
	
	private auto matchParameter(Expression arg, Parameter param) {
		if(param.isReference && !canConvert(arg.type.qualifier, param.type.qualifier)) {
			return pass.raiseCondition!Expression(arg.location, "Can't pass argument by ref.");
		}
		
		arg = pass.implicitCast(arg.location, param.type, arg);
		
		// test if we can pass by ref.
		if(param.isReference && !arg.isLvalue) {
			return pass.raiseCondition!Expression(arg.location, "Argument isn't a lvalue.");
		}
		
		return arg;
	}
	
	Expression visit(CallExpression c) {
		c.callee = visit(c.callee);
		c.arguments = c.arguments.map!(a => visit(a)).array();
		
		if(auto asPolysemous = cast(PolysemousExpression) c.callee) {
			auto candidates = asPolysemous.expressions.filter!((e) {
				if(auto asFunType = cast(FunctionType) e.type) {
					if(asFunType.isVariadic) {
						return c.arguments.length >= asFunType.parameters.length;
					} else {
						return c.arguments.length == asFunType.parameters.length;
					}
				}
				
				assert(0, "type is not a function type");
			}).map!(c => visit(c));
			
			enum MatchLevel {
				Not,
				TypeConvert,
				QualifierConvert,
				Exact,
			}
			
			// Ensure we build error instead of failing.
			auto oldBuildErrorNode = buildErrorNode;
			scope(exit) buildErrorNode = oldBuildErrorNode;
			
			buildErrorNode = true;
			
			auto level = MatchLevel.Not;
			Expression match;
			CandidateLoop: foreach(candidate; candidates) {
				auto type = cast(FunctionType) candidate.type;
				assert(type, "We should have filtered function at this point.");
				
				auto candidateLevel = MatchLevel.Exact;
				foreach(arg, param; lockstep(c.arguments, type.parameters)) {
					auto candidateArg = matchParameter(arg, param);
					
					// If candidateArg and arg are the same, we have an exact match.
					if(candidateArg !is arg) {
						if(typeid(candidateArg) is typeid(ErrorExpression)) {
							// If the call is impossible, go to next candidate.
							continue CandidateLoop;
						} else if(typeid(candidateArg) is typeid(BitCastExpression)) {
							// We have a bitcast.
							// FIXME: actually wrong :D
							candidateLevel = min(candidateLevel, MatchLevel.QualifierConvert);
						} else {
							candidateLevel = min(candidateLevel, MatchLevel.TypeConvert);
						}
						
						// If the match level is too low, let's go to next candidate directly.
						if(candidateLevel < level) {
							continue CandidateLoop;
						}
					}
				}
				
				if(candidateLevel > level) {
					level = candidateLevel;
					match = candidate;
				} else if(candidateLevel == level) {
					// Multiple candidates.
					return pass.raiseCondition!Expression(c.location, "ambigusous function call.");
				}
			}
			
			if(!match) {
				return pass.raiseCondition!Expression(c.location, "No candidate for function call.");
			}
			
			c.callee = match;
		}
		
		Parameter[] params;
		if(auto type = cast(FunctionType) c.callee.type) {
			params = type.parameters;
			c.type = type.returnType;
		} else {
			return pass.raiseCondition!Expression(c.location, "You must call function or delegates, you fool !!!");
		}
		
		assert(c.arguments.length >= params.length);
		
		foreach(ref arg, param; lockstep(c.arguments, params)) {
			arg = matchParameter(arg, param);
		}
		
		return c;
	}
	
	Expression visit(FieldExpression e) {
		e.expression = visit(e.expression);
		e.field = cast(FieldDeclaration) scheduler.require(e.field, Step.Signed);
		
		e.type = e.field.type;
		
		return e;
	}
	
	// TODO: handle overload sets.
	Expression visit(DelegateExpression e) {
		e.funptr = visit(e.funptr);
		
		if(auto funType = cast(FunctionType) e.funptr.type) {
			if(typeid(funType) !is typeid(FunctionType)) {
				return pass.raiseCondition!Expression(e.location, "Can't create delegate.");
			}
			
			if(funType.isVariadic || funType.parameters.length > 0) {
				auto contextParam = funType.parameters[0];
				
				e.context = matchParameter(e.context, contextParam);
				e.type = new DelegateType(e.location, funType.linkage, funType.returnType, contextParam, funType.parameters[1 .. $], funType.isVariadic);
				
				return e;
			}
		}
		
		return pass.raiseCondition!Expression(e.location, "Can't create delegate.");
	}
	
	Expression visit(VirtualDispatchExpression e) {
		e.method = cast(MethodDeclaration) scheduler.require(e.method, Step.Signed);
		
		if(auto funType = cast(FunctionType) e.method.type) {
			if(funType.isVariadic || funType.parameters.length > 0) {
				auto thisParam = funType.parameters[0];
				
				e.expression = matchParameter(e.expression, thisParam);
				e.type = new DelegateType(e.location, funType.linkage, funType.returnType, thisParam, funType.parameters[1 .. $], funType.isVariadic);
				
				return e;
			}
		}
		
		return pass.raiseCondition!Expression(e.location, "Can't create delegate.");
	}
	
	Expression visit(NewExpression e) {
		assert(e.arguments.length == 0, "constructor not supported");
		
		e.type = pass.visit(e.type);
		
		return e;
	}
	
	Expression visit(ThisExpression e) {
		e.type = thisType;
		
		return e;
	}
	
	Expression visit(IndexExpression e) {
		e.indexed = visit(e.indexed);
		
		if(auto asSlice = cast(SliceType) e.indexed.type) {
			e.type = asSlice.type;
		} else if(auto asPointer = cast(PointerType) e.indexed.type) {
			e.type = asPointer.type;
		} else if(auto asStaticArray = cast(StaticArrayType) e.indexed.type) {
			e.type = asStaticArray.type;
		} else {
			return pass.raiseCondition!Expression(e.location, "Can't index " ~ typeid({ return e.indexed; }()).toString());
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
		} else {
			return pass.raiseCondition!Expression(e.location, "Can't slice " ~ typeid({ return e.indexed; }()).toString());
		}
		
		e.type = new SliceType(e.location, e.type);
		
		e.first = e.first.map!(e => visit(e)).array();
		e.second = e.second.map!(e => visit(e)).array();
		
		return e;
	}
	
	Expression visit(SizeofExpression e) {
		return makeLiteral(e.location, sizeofCalculator.visit(e.argument));
	}
	
	Expression visit(AssertExpression e) {
		auto c = visit(e.condition);
		e.condition = explicitCast(c.location, new BooleanType(c.location), c);
		
		if(e.message) {
			// FIXME: cast to string.
			e.message = evaluate(visit(e.message));
		}
		
		e.type = new VoidType(e.location);
		
		return e;
	}
	
	Expression visit(IdentifierExpression e) {
		return pass.visit(e.identifier).apply!((identified) {
			static if(is(typeof(identified) : Expression)) {
				return visit(identified);
			} else {
				return pass.raiseCondition!Expression(e.location, e.identifier.name ~ " isn't an expression.");
			}
		})();
	}
	
	Expression visit(SymbolExpression e) {
		auto s = cast(ExpressionSymbol) scheduler.require(e.symbol, Step.Signed);
		
		e.symbol = s;
		e.type = s.type;
		
		return e;
	}
	
	// Will be remove by cast operation.
	Expression visit(DefaultInitializer di) {
		return di;
	}
}

