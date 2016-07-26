module d.parser.expression;

import d.ast.expression;
import d.ast.identifier;

import d.ir.expression;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.identifier;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

/**
 * Parse Expression
 */
AstExpression parseExpression(ParseMode mode = ParseMode.Greedy)(ref TokenRange trange) {
	auto lhs = trange.parsePrefixExpression!mode();
	return trange.parseAstBinaryExpression!(
		TokenType.Comma,
		AstBinaryOp.Comma,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseAssignExpression(e);
		}
	)(lhs);
}

/**
 * Template used to parse basic AstBinaryExpressions.
 */
private AstExpression parseAstBinaryExpression(
	TokenType tokenType,
	AstBinaryOp op,
	alias parseNext,
	R,
)(ref R trange, AstExpression lhs) {
	lhs = parseNext(trange, lhs);
	Location location = lhs.location;
	
	while (trange.front.type == tokenType) {
		trange.popFront();
		
		auto rhs = trange.parsePrefixExpression();
		rhs = parseNext(trange, rhs);
		
		location.spanTo(rhs.location);
		lhs = new AstBinaryExpression(location, op, lhs, rhs);
	}
	
	return lhs;
}

/**
 * Parse assignement expressions.
 */
AstExpression parseAssignExpression(ref TokenRange trange) {
	return trange.parseAssignExpression(trange.parsePrefixExpression());
}

AstExpression parseAssignExpression(ref TokenRange trange, AstExpression lhs) {
	lhs = trange.parseTernaryExpression(lhs);
	Location location = lhs.location;
	
	void processToken(AstBinaryOp op) {
		trange.popFront();
		
		auto rhs = trange.parsePrefixExpression();
		rhs = trange.parseAssignExpression(rhs);
		
		location.spanTo(rhs.location);
		
		lhs = new AstBinaryExpression(location, op, lhs, rhs);
	}
	
	switch(trange.front.type) with(AstBinaryOp) with(TokenType) {
		case Equal :
			processToken(Assign);
			break;
		
		case PlusEqual :
			processToken(AddAssign);
			break;
		
		case MinusEqual :
			processToken(SubAssign);
			break;
		
		case StarEqual :
			processToken(MulAssign);
			break;
		
		case SlashEqual :
			processToken(DivAssign);
			break;
		
		case PercentEqual :
			processToken(RemAssign);
			break;
		
		case AmpersandEqual :
			processToken(AndAssign);
			break;
		
		case PipeEqual :
			processToken(OrAssign);
			break;
		
		case CaretEqual :
			processToken(XorAssign);
			break;
		
		case TildeEqual :
			processToken(ConcatAssign);
			break;
		
		case LessLessEqual :
			processToken(LeftShiftAssign);
			break;
		
		case MoreMoreEqual :
			processToken(SignedRightShiftAssign);
			break;
		
		case MoreMoreMoreEqual :
			processToken(UnsignedRightShiftAssign);
			break;
		
		case CaretCaretEqual :
			processToken(PowAssign);
			break;
		
		default :
			// No assignement.
			break;
	}
	
	return lhs;
}

/**
 * Parse ?:
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseTernaryExpression(ref TokenRange trange) {
	return trange.parseTernaryExpression(trange.parsePrefixExpression());
}

AstExpression parseTernaryExpression(ref TokenRange trange, AstExpression condition) {
	condition = trange.parseLogicalOrExpression(condition);
	
	if (trange.front.type == TokenType.QuestionMark) {
		Location location = condition.location;
		
		trange.popFront();
		auto ifTrue = trange.parseExpression();
		
		trange.match(TokenType.Colon);
		auto ifFalse = trange.parseTernaryExpression();
		
		location.spanTo(ifFalse.location);
		return new AstTernaryExpression(location, condition, ifTrue, ifFalse);
	}
	
	return condition;
}

/**
 * Parse ||
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseLogicalOrExpression(ref TokenRange trange) {
	return trange.parseLogicalOrExpression(trange.parsePrefixExpression());
}

auto parseLogicalOrExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(
		TokenType.PipePipe,
		AstBinaryOp.LogicalOr,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseLogicalAndExpression(e);
		}
	)(lhs);
}

/**
 * Parse &&
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseLogicalAndExpression(ref TokenRange trange) {
	return trange.parseLogicalAndExpression(trange.parsePrefixExpression());
}

auto parseLogicalAndExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(
		TokenType.AmpersandAmpersand,
		AstBinaryOp.LogicalAnd,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseBitwiseOrExpression(e);
		}
	)(lhs);
}

/**
 * Parse |
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseBitwiseOrExpression(ref TokenRange trange) {
	return trange.parseBitwiseOrExpression(trange.parsePrefixExpression());
}

auto parseBitwiseOrExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(
		TokenType.Pipe,
		AstBinaryOp.Or,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseBitwiseXorExpression(e);
		}
	)(lhs);
}

/**
 * Parse ^
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseBitwiseXorExpression(ref TokenRange trange) {
	return trange.parseBitwiseXorExpression(trange.parsePrefixExpression());
}

auto parseBitwiseXorExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(
		TokenType.Caret,
		AstBinaryOp.Xor,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseBitwiseAndExpression(e);
		}
	)(lhs);
}

/**
 * Parse &
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseBitwiseAndExpression(ref TokenRange trange) {
	return trange.parseBitwiseAndExpression(trange.parsePrefixExpression());
}

auto parseBitwiseAndExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(
		TokenType.Ampersand,
		AstBinaryOp.And,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseComparaisonExpression(e);
		}
	)(lhs);
}

/**
 * Parse ==, != and comparaisons
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseComparaisonExpression(ref TokenRange trange) {
	return trange.parseComparaisonExpression(trange.parsePrefixExpression());
}

AstExpression parseComparaisonExpression(ref TokenRange trange, AstExpression lhs) {
	lhs = trange.parseShiftExpression(lhs);
	Location location = lhs.location;
	
	void processToken(AstBinaryOp op) {
		trange.popFront();
		
		auto rhs = trange.parseShiftExpression();
		
		location.spanTo(rhs.location);
		lhs = new AstBinaryExpression(location, op, lhs, rhs);
	}
	
	switch(trange.front.type) with(TokenType) {
		case EqualEqual :
			processToken(AstBinaryOp.Equal);
			break;
		
		case BangEqual :
			processToken(AstBinaryOp.NotEqual);
			break;
		
		case More:
			processToken(AstBinaryOp.Greater);
			break;
		
		case MoreEqual:
			processToken(AstBinaryOp.GreaterEqual);
			break;
		
		case Less :
			processToken(AstBinaryOp.Less);
			break;
		
		case LessEqual :
			processToken(AstBinaryOp.LessEqual);
			break;
		
		case BangLessMoreEqual:
			processToken(AstBinaryOp.Unordered);
			break;
		
		case BangLessMore:
			processToken(AstBinaryOp.UnorderedEqual);
			break;
		
		case LessMore:
			processToken(AstBinaryOp.LessGreater);
			break;
		
		case LessMoreEqual:
			processToken(AstBinaryOp.LessEqualGreater);
			break;
		
		case BangMore:
			processToken(AstBinaryOp.UnorderedLessEqual);
			break;
		
		case BangMoreEqual:
			processToken(AstBinaryOp.UnorderedLess);
			break;
		
		case BangLess:
			processToken(AstBinaryOp.UnorderedGreaterEqual);
			break;
		
		case BangLessEqual:
			processToken(AstBinaryOp.UnorderedGreater);
			break;
		
		case Is :
			processToken(AstBinaryOp.Identical);
			break;
		
		case In :
			processToken(AstBinaryOp.In);
			break;
		
		case Bang :
			trange.popFront();
			switch(trange.front.type) {
				case Is :
					processToken(AstBinaryOp.NotIdentical);
					break;
				
				case In :
					processToken(AstBinaryOp.NotIn);
					break;
				
				default :
					trange.match(TokenType.Begin);
					break;
			}
			
			break;
		
		default :
			// We have no comparaison, so we just return.
			break;
	}
	
	return lhs;
}

/**
 * Parse <<, >> and >>>
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseShiftExpression(ref TokenRange trange) {
	return trange.parseShiftExpression(trange.parsePrefixExpression());
}

AstExpression parseShiftExpression(ref TokenRange trange, AstExpression lhs) {
	lhs = trange.parseAddExpression(lhs);
	Location location = lhs.location;
	
	while(1) {
		void processToken(AstBinaryOp op) {
			trange.popFront();
			
			auto rhs = trange.parseAddExpression();
			
			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}
		
		switch(trange.front.type) with(AstBinaryOp) with(TokenType) {
			case LessLess :
				processToken(LeftShift);
				break;
			
			case MoreMore :
				processToken(SignedRightShift);
				break;
			
			case MoreMoreMore :
				processToken(UnsignedRightShift);
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Parse +, - and ~
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseAddExpression(ref TokenRange trange) {
	return trange.parseAddExpression(trange.parsePrefixExpression());
}

AstExpression parseAddExpression(ref TokenRange trange, AstExpression lhs) {
	lhs = trange.parseMulExpression(lhs);
	Location location = lhs.location;
	
	while(1) {
		void processToken(AstBinaryOp op) {
			trange.popFront();
			
			auto rhs = trange.parseMulExpression();
			
			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}
		
		switch(trange.front.type) with(AstBinaryOp) with(TokenType) {
			case Plus :
				processToken(Add);
				break;
			
			case Minus :
				processToken(Sub);
				break;
			
			case Tilde :
				processToken(Concat);
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Parse *, / and %
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseMulExpression(ref TokenRange trange) {
	return trange.parseMulExpression(trange.parsePrefixExpression());
}

AstExpression parseMulExpression(ref TokenRange trange, AstExpression lhs) {
	Location location = lhs.location;
	
	while(1) {
		void processToken(AstBinaryOp op) {
			trange.popFront();
			
			auto rhs = trange.parsePrefixExpression();
			
			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}
		
		switch(trange.front.type) with(AstBinaryOp) with(TokenType) {
			case Star :
				processToken(Mul);
				break;
			
			case Slash :
				processToken(Div);
				break;
			
			case Percent :
				processToken(Rem);
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Unary prefixes
 */
private AstExpression parsePrefixExpression(
	ParseMode mode = ParseMode.Greedy,
)(ref TokenRange trange) {
	AstExpression result;
	
	void processToken(UnaryOp op) {
		Location location = trange.front.location;
		trange.popFront();
		
		// Drop mode on purpose.
		result = trange.parsePrefixExpression();
		
		location.spanTo(result.location);
		result = new AstUnaryExpression(location, op, result);
	}
	
	switch(trange.front.type) with(TokenType) {
		case Ampersand :
			processToken(UnaryOp.AddressOf);
			break;
		
		case PlusPlus :
			processToken(UnaryOp.PreInc);
			break;
		
		case MinusMinus :
			processToken(UnaryOp.PreDec);
			break;
		
		case Star :
			processToken(UnaryOp.Dereference);
			break;
		
		case Plus :
			processToken(UnaryOp.Plus);
			break;
		
		case Minus :
			processToken(UnaryOp.Minus);
			break;
		
		case Bang :
			processToken(UnaryOp.Not);
			break;
		
		case Tilde :
			processToken(UnaryOp.Complement);
			break;
		
		// TODO: parse qualifier casts.
		case Cast :
			Location location = trange.front.location;
			trange.popFront();
			trange.match(OpenParen);
			
			switch(trange.front.type) {
				case CloseParen :
					assert(0, "cast() isn't supported.");
				
				default :
					auto type = trange.parseType();
					trange.match(CloseParen);
					
					result = trange.parsePrefixExpression();
					location.spanTo(result.location);
					
					result = new AstCastExpression(location, type, result);
			}
			
			break;
		
		default :
			result = trange.parsePrimaryExpression();
			result = trange.parsePostfixExpression!mode(result);
	}
	
	// Ensure we do not screwed up.
	assert(result);
	
	return trange.parsePowExpression(result);
}

AstExpression parsePrimaryExpression(ref TokenRange trange) {
	Location location = trange.front.location;
	
	switch(trange.front.type) with(TokenType) {
		// Identified expressions
		case Identifier :
			return trange.parseIdentifierExpression(trange.parseIdentifier());
		
		case New :
			trange.popFront();
			auto type = trange.parseType();
			auto args = trange.parseArguments!OpenParen();
			
			location.spanTo(trange.front.location);
			return new AstNewExpression(location, type, args);
		
		case Dot :
			return trange.parseIdentifierExpression(trange.parseDotIdentifier());
		
		case This :
			trange.popFront();
			return new ThisExpression(location);
		
		case Super :
			trange.popFront();
			return new SuperExpression(location);
		
		case True :
			trange.popFront();
			return new BooleanLiteral(location, true);
		
		case False :
			trange.popFront();
			return new BooleanLiteral(location, false);
		
		case Null :
			trange.popFront();
			return new NullLiteral(location);
		
		case IntegerLiteral :
			return trange.parseIntegerLiteral();
		
		case StringLiteral :
			auto name = trange.front.name;
			trange.popFront();
			
			// XXX: Use name for string once CTFE do not return node ?
			return new d.ir.expression.StringLiteral(location, name.toString(trange.context));
		
		case CharacterLiteral :
			auto str = trange.front.name.toString(trange.context);
			assert(str.length == 1);
			
			trange.popFront();
			
			import d.common.builtintype : BuiltinType;
			return new d.ir.expression.CharacterLiteral(location, str[0], BuiltinType.Char);
		
		case OpenBracket :
			AstExpression[] keys, values;
			do {
				trange.popFront();
				auto value = trange.parseAssignExpression();
				
				if(trange.front.type == Colon) {
					keys ~= value;
					trange.popFront();
					values ~= trange.parseAssignExpression();
				} else {
					values ~= value;
				}
			} while(trange.front.type == Comma);
			
			location.spanTo(trange.front.location);
			trange.match(CloseBracket);
			
			return new AstArrayLiteral(location, values);
		
		case OpenBrace :
			return new DelegateLiteral(trange.parseBlock());
		
		case Function :
		case Delegate :
			assert(0, "Functions or Delegates not implemented ");
		
		case __File__ :
			trange.popFront();
			return new __File__Literal(location);
		
		case __Line__ :
			trange.popFront();
			return new __Line__Literal(location);
		
		case Dollar :
			trange.popFront();
			return new DollarExpression(location);
		
		case Typeid :
			trange.popFront();
			trange.match(OpenParen);
			
			return trange.parseAmbiguous!(delegate AstExpression(parsed) {
				location.spanTo(trange.front.location);
				trange.match(CloseParen);
				
				import d.ast.type;
				
				alias T = typeof(parsed);
				static if(is(T : AstType)) {
					return new AstStaticTypeidExpression(location, parsed);
				} else static if(is(T : AstExpression)) {
					return new AstTypeidExpression(location, parsed);
				} else {
					return new IdentifierTypeidExpression(location, parsed);
				}
			})();
		
		case Is :
			return trange.parseIsExpression();
		
		case Mixin :
			import d.parser.conditional;
			return trange.parseMixin!AstExpression();
		
		case OpenParen :
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!OpenParen();
			
			switch(matchingParen.front.type) {
				case Dot:
					trange.popFront();
					return trange.parseAmbiguous!((parsed) {
						trange.match(CloseParen);
						trange.match(Dot);
						
						auto qi = trange.parseQualifiedIdentifier(
							location,
							parsed,
						);
						return trange.parseIdentifierExpression(qi);
					})();
				
				case OpenBrace:
					import d.parser.declaration;
					bool isVariadic;
					auto params = trange.parseParameters(isVariadic);
					
					auto block = trange.parseBlock();
					location.spanTo(block.location);
					
					return new DelegateLiteral(location, params, isVariadic, block);
				
				case EqualMore:
					import d.parser.declaration;
					bool isVariadic;
					auto params = trange.parseParameters(isVariadic);
					assert(!isVariadic, "Variadic lambda not supported");
					
					trange.match(EqualMore);
					
					auto value = trange.parseExpression();
					location.spanTo(value.location);
					
					return new Lambda(location, params, value);
				
				default:
					trange.popFront();
					auto expression = trange.parseExpression();
					
					location.spanTo(trange.front.location);
					trange.match(CloseParen);
					
					return new ParenExpression(location, expression);
			}
		
		default:
			// Our last resort are type.identifier expressions.
			auto type = trange.parseType!(ParseMode.Reluctant)();
			trange.match(Dot);
			
			// FIXME: Or type() {} expressions.
			return trange.parseIdentifierExpression(
				trange.parseQualifiedIdentifier(location, type),
			);
	}
}

/**
 * Parse postfix ++, --, (...), [...], .identifier
 */
AstExpression parsePostfixExpression(ParseMode mode)(ref TokenRange trange, AstExpression e) {
	Location location = e.location;
	
	while(1) {
		switch(trange.front.type) with(TokenType) {
			case PlusPlus :
				location.spanTo(trange.front.location);
				trange.popFront();
				
				e = new AstUnaryExpression(location, UnaryOp.PostInc, e);
				break;
			
			case MinusMinus :
				location.spanTo(trange.front.location);
				trange.popFront();
				
				e = new AstUnaryExpression(location, UnaryOp.PostDec, e);
				break;
			
			case OpenParen :
				auto args = trange.parseArguments!OpenParen();
				
				location.spanTo(trange.front.location);
				e = new AstCallExpression(location, e, args);
				
				break;
			
			// TODO: Indices, Slices.
			case OpenBracket :
				trange.popFront();
				
				if (trange.front.type == CloseBracket) {
					// We have a slicing operation here.
					assert(0, "Slice expressions can not be parsed yet");
				} else {
					auto args = trange.parseArguments();
					switch(trange.front.type) {
						case CloseBracket :
							location.spanTo(trange.front.location);
							e = new AstIndexExpression(location, e, args);
							
							break;
						
						case DotDot :
							trange.popFront();
							auto second = trange.parseArguments();
							
							location.spanTo(trange.front.location);
							e = new AstSliceExpression(location, e, args, second);
							
							break;
						
						default :
							// TODO: error message that make sense.
							trange.match(Begin);
							break;
					}
				}
				
				trange.match(CloseBracket);
				break;
			
			static if(mode == ParseMode.Greedy) {
			case Dot :
				trange.popFront();
				
				e = trange.parseIdentifierExpression(
					trange.parseQualifiedIdentifier(location, e),
				);
				
				break;
			}
			
			default :
				return e;
		}
	}
}

/**
 * Parse ^^
 */
private
AstExpression parsePowExpression(ref TokenRange trange, AstExpression expr) {
	Location location = expr.location;
	
	while (trange.front.type == TokenType.CaretCaret) {
		trange.popFront();
		AstExpression power = trange.parsePrefixExpression();
		location.spanTo(power.location);
		expr = new AstBinaryExpression(location, AstBinaryOp.Pow, expr, power);
	}
	
	return expr;
}

/**
 * Parse unary is expression.
 */
private auto parseIsExpression(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Is);
	trange.match(TokenType.OpenParen);
	
	auto type = trange.parseType();
	
	// Handle alias throw is expression.
	if (trange.front.type == TokenType.Identifier) {
		trange.popFront();
	}
	
	switch(trange.front.type) with(TokenType) {
		case Colon :
			trange.popFront();
			trange.parseType();
			break;
		
		case EqualEqual :
			trange.popFront();
			
			switch(trange.front.type) {
				case Struct, Union, Class, Interface, Enum, Function, Delegate :
				case Super, Const, Immutable, Inout, Shared, Return :
					assert(0, "Not implemented.");
				
				default :
					trange.parseType();
			}
			
			break;
		
		default :
			break;
	}
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.CloseParen);
	
	return new IsExpression(location, type);
}

/**
 * Parse identifier expression
 */
AstExpression parseIdentifierExpression(ref TokenRange trange, Identifier i) {
	if (trange.front.type != TokenType.OpenParen) {
		return new IdentifierExpression(i);
	}
	
	auto args = trange.parseArguments!(TokenType.OpenParen)();
	
	auto location = i.location;
	location.spanTo(trange.front.location);
	return new IdentifierCallExpression(location, i, args);
}

/**
 * Parse function arguments
 */
AstExpression[] parseArguments(TokenType openTokenType)(ref TokenRange trange) {
	alias closeTokenType = MatchingDelimiter!openTokenType;
	
	trange.match(openTokenType);
	
	if (trange.front.type == closeTokenType) {
		trange.match(closeTokenType);
		return [];
	}
	
	AstExpression[] args;
	while(true) {
		args ~= trange.parseAssignExpression();
		
		if (trange.front.type != TokenType.Comma) {
			break;
		}
		
		trange.popFront();
		
		if (trange.front.type == closeTokenType) {
			break;
		}
	}
	
	trange.match(closeTokenType);
	return args;
}

AstExpression[] parseArguments(ref TokenRange trange) {
	AstExpression[] args = [trange.parseAssignExpression()];
	while(trange.front.type == TokenType.Comma) {
		trange.popFront();
		
		args ~= trange.parseAssignExpression();
	}
	
	return args;
}

/**
 * Parse integer literals
 */
private IntegerLiteral parseIntegerLiteral(ref TokenRange trange) {
	Location location = trange.front.location;
	
	// Consider computing the value in the lexer and make it a fack string.
	// This would avoid the duplication with code here and probably
	// would be faster as well.
	auto strVal = trange.front.name.toString(trange.context);
	assert(strVal.length > 0);
	
	trange.match(TokenType.IntegerLiteral);
	
	bool isUnsigned, isLong;
	if (strVal.length > 1) {
		switch (strVal[$ - 1]) {
			case 'u', 'U' :
				isUnsigned = true;
				
				auto penultimo = strVal[$ - 2];
				if (penultimo == 'l' || penultimo == 'L') {
					isLong = true;
					strVal = strVal[0 .. $ - 2];
				} else {
					strVal = strVal[0 .. $ - 1];
				}
				
				break;
			
			case 'l', 'L' :
				isLong = true;
				
				auto penultimo = strVal[$ - 2];
				if (penultimo == 'u' || penultimo == 'U') {
					isUnsigned = true;
					strVal = strVal[0 .. $ - 2];
				} else {
					strVal = strVal[0 .. $ - 1];
				}
				
				break;
			
			default :
				break;
		}
	}
	
	ulong value;
	
	assert(strVal.length > 0);
	if (strVal[0] != '0' || strVal.length < 3) {
		goto ParseDec;
	}
	
	switch(strVal[1]) {
		case 'x', 'X':
			value = strToHexInt(strVal[2 .. $]);
			goto CreateLiteral;
		
		case 'b', 'B' :
			value = strToBinInt(strVal[2 .. $]);
			goto CreateLiteral;
		
		default :
			// Break to parse as decimal.
			break;
	}
	
	ParseDec: value = strToDecInt(strVal);
	
	CreateLiteral :
	
	import d.common.builtintype;
	auto type = isUnsigned
		? ((isLong || value > uint.max) ? BuiltinType.Ulong : BuiltinType.Uint)
		: ((isLong || value > int.max) ? BuiltinType.Long : BuiltinType.Int);
	
	return new IntegerLiteral(location, value, type);
}

ulong strToDecInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} body {
	ulong ret = 0;
	
	for (uint i = 0; i < s.length; i++) {
		if (s[i] == '_') continue;
		
		ret *= 10;
		
		auto d = s[i] - '0';
		assert(d < 10, "Only digits are expected here");
		ret += d;
	}
	
	return ret;
}

unittest {
	assert(strToDecInt("0") == 0);
	assert(strToDecInt("42") == 42);
	assert(strToDecInt("1234567890") == 1234567890);
	assert(strToDecInt("18446744073709551615") == 18446744073709551615UL);
	assert(strToDecInt("34_56") == 3456);
}

ulong strToBinInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} body {
	ulong ret = 0;
	
	for (uint i = 0; i < s.length; i++) {
		if (s[i] == '_') continue;
		
		ret <<= 1;
		auto d = s[i] - '0';
		assert(d < 2, "Only 0 and 1 are expected here");
		ret |= d;
	}
	
	return ret;
}

unittest {
	assert(strToBinInt("0") == 0);
	assert(strToBinInt("1010") == 10);
	assert(strToBinInt("0101010") == 42);
	assert(strToBinInt(
		"1111111111111111111111111111111111111111111111111111111111111111",
	) == 18446744073709551615UL);
	assert(strToBinInt("11_101_00") == 116);
}

ulong strToHexInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} body {
	ulong ret = 0;
	
	for (uint i = 0; i < s.length; i++) {
		// TODO: Filter these out at lexing.
		if (s[i] == '_') continue;
		
		// XXX: This would allow to reduce data dependacy here by using
		// the string length and shifting the whole amount at once.
		ret *= 16;
		
		auto d = s[i] - '0';
		if (d < 10) {
			ret += d;
			continue;
		}
		
		auto h = (s[i] | 0x20) - 'a' + 10;
		assert(h - 10 < 6, "Only hex digits are expected here");
		ret += h;
	}
	
	return ret;
}

unittest {
	assert(strToHexInt("0") == 0);
	assert(strToHexInt("A") == 10);
	assert(strToHexInt("a") == 10);
	assert(strToHexInt("F") == 15);
	assert(strToHexInt("f") == 15);
	assert(strToHexInt("42") == 66);
	assert(strToHexInt("AbCdEf0") == 180150000);
	assert(strToHexInt("12345aBcDeF") == 1251004370415);
	assert(strToHexInt("FFFFFFFFFFFFFFFF") == 18446744073709551615UL);
	assert(strToHexInt("a_B_c") == 2748);
}
