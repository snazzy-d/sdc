module d.parser.expression;

import d.ast.expression;
import d.ast.identifier;

import d.ir.expression;
import d.ir.type;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.identifier;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

/**
 * Parse Expression
 */
AstExpression parseExpression(ParseMode mode = ParseMode.Greedy, R)(ref R trange) if(isTokenRange!R) {
	auto lhs = trange.parsePrefixExpression!mode();
	return trange.parseAstBinaryExpression!(
		TokenType.Comma,
		BinaryOp.Comma,
		function AstExpression(ref R trange, AstExpression e) {
			return trange.parseAssignExpression(e);
		}
	)(lhs);
}

/**
 * Template used to parse basic AstBinaryExpressions.
 */
private AstExpression parseAstBinaryExpression(TokenType tokenType, BinaryOp op, alias parseNext, R)(ref R trange, AstExpression lhs) {
	lhs = parseNext(trange, lhs);
	Location location = lhs.location;
	
	while(trange.front.type == tokenType) {
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
AstExpression parseAssignExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseAssignExpression(trange.parsePrefixExpression());
}

AstExpression parseAssignExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	lhs = trange.parseConditionalExpression(lhs);
	Location location = lhs.location;
	
	void processToken(BinaryOp op) {
		trange.popFront();
		
		auto rhs = trange.parsePrefixExpression();
		rhs = trange.parseAssignExpression(rhs);
		
		location.spanTo(rhs.location);
		
		lhs = new AstBinaryExpression(location, op, lhs, rhs);
	}
	
	switch(trange.front.type) with(TokenType) {
		case Assign :
			processToken(BinaryOp.Assign);
			break;
		
		case PlusAssign :
			processToken(BinaryOp.AddAssign);
			break;
		
		case MinusAssign :
			processToken(BinaryOp.SubAssign);
			break;
		
		case StarAssign :
			processToken(BinaryOp.MulAssign);
			break;
		
		case SlashAssign :
			processToken(BinaryOp.DivAssign);
			break;
		
		case PercentAssign :
			processToken(BinaryOp.ModAssign);
			break;
		
		case AmpersandAssign :
			processToken(BinaryOp.BitwiseAndAssign);
			break;
		
		case PipeAssign :
			processToken(BinaryOp.BitwiseOrAssign);
			break;
		
		case CaretAssign :
			processToken(BinaryOp.BitwiseXorAssign);
			break;
		
		case TildeAssign :
			processToken(BinaryOp.ConcatAssign);
			break;
		
		case DoubleLessAssign :
			processToken(BinaryOp.LeftShiftAssign);
			break;
		
		case DoubleMoreAssign :
			processToken(BinaryOp.SignedRightShiftAssign);
			break;
		
		case TripleMoreAssign :
			processToken(BinaryOp.UnsignedRightShiftAssign);
			break;
		
		case DoubleCaretAssign :
			processToken(BinaryOp.PowAssign);
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
AstExpression parseConditionalExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseConditionalExpression(trange.parsePrefixExpression());
}

AstExpression parseConditionalExpression(R)(ref R trange, AstExpression condition) if(isTokenRange!R) {
	condition = trange.parseLogicalOrExpression(condition);
	
	if(trange.front.type == TokenType.QuestionMark) {
		Location location = condition.location;
		
		trange.popFront();
		auto ifTrue = trange.parseExpression();
		
		trange.match(TokenType.Colon);
		auto ifFalse = trange.parseConditionalExpression();
		
		location.spanTo(ifFalse.location);
		return new AstConditionalExpression(location, condition, ifTrue, ifFalse);
	}
	
	return condition;
}

/**
 * Parse ||
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseLogicalOrExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseLogicalOrExpression(trange.parsePrefixExpression());
}

auto parseLogicalOrExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	return trange.parseAstBinaryExpression!(
		TokenType.DoublePipe,
		BinaryOp.LogicalOr,
		function AstExpression(ref R trange, AstExpression e) {
			return trange.parseLogicalAndExpression(e);
		}
	)(lhs);
}

/**
 * Parse &&
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseLogicalAndExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseLogicalAndExpression(trange.parsePrefixExpression());
}

auto parseLogicalAndExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	return trange.parseAstBinaryExpression!(
		TokenType.DoubleAmpersand,
		BinaryOp.LogicalAnd,
		function AstExpression(ref R trange, AstExpression e) {
			return trange.parseBitwiseOrExpression(e);
		}
	)(lhs);
}

/**
 * Parse |
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseBitwiseOrExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseBitwiseOrExpression(trange.parsePrefixExpression());
}

auto parseBitwiseOrExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	return trange.parseAstBinaryExpression!(
		TokenType.Pipe,
		BinaryOp.BitwiseOr,
		function AstExpression(ref R trange, AstExpression e) {
			return trange.parseBitwiseXorExpression(e);
		}
	)(lhs);
}

/**
 * Parse ^
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseBitwiseXorExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseBitwiseXorExpression(trange.parsePrefixExpression());
}

auto parseBitwiseXorExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	return trange.parseAstBinaryExpression!(
		TokenType.Caret,
		BinaryOp.BitwiseXor,
		function AstExpression(ref R trange, AstExpression e) {
			return trange.parseBitwiseAndExpression(e);
		}
	)(lhs);
}

/**
 * Parse &
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseBitwiseAndExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseBitwiseAndExpression(trange.parsePrefixExpression());
}

auto parseBitwiseAndExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	return trange.parseAstBinaryExpression!(
		TokenType.Ampersand,
		BinaryOp.BitwiseAnd,
		function AstExpression(ref R trange, AstExpression e) {
			return trange.parseComparaisonExpression(e);
		}
	)(lhs);
}

/**
 * Parse ==, != and comparaisons
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseComparaisonExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseComparaisonExpression(trange.parsePrefixExpression());
}

AstExpression parseComparaisonExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	lhs = trange.parseShiftExpression(lhs);
	Location location = lhs.location;
	
	void processToken(BinaryOp op) {
		trange.popFront();
		
		auto rhs = trange.parseShiftExpression();
		
		location.spanTo(rhs.location);
		lhs = new AstBinaryExpression(location, op, lhs, rhs);
	}
	
	switch(trange.front.type) with(TokenType) {
		case DoubleAssign :
			processToken(BinaryOp.Equal);
			break;
		
		case BangAssign :
			processToken(BinaryOp.NotEqual);
			break;
		
		case More:
			processToken(BinaryOp.Greater);
			break;
		
		case MoreAssign:
			processToken(BinaryOp.GreaterEqual);
			break;
		
		case Less :
			processToken(BinaryOp.Less);
			break;
		
		case LessAssign :
			processToken(BinaryOp.LessEqual);
			break;
		
		case BangLessMoreAssign:
			processToken(BinaryOp.Unordered);
			break;
		
		case BangLessMore:
			processToken(BinaryOp.UnorderedEqual);
			break;
		
		case LessMore:
			processToken(BinaryOp.LessGreater);
			break;
		
		case LessMoreAssign:
			processToken(BinaryOp.LessEqualGreater);
			break;
		
		case BangMore:
			processToken(BinaryOp.UnorderedLessEqual);
			break;
		
		case BangMoreAssign:
			processToken(BinaryOp.UnorderedLess);
			break;
		
		case BangLess:
			processToken(BinaryOp.UnorderedGreaterEqual);
			break;
		
		case BangLessAssign:
			processToken(BinaryOp.UnorderedGreater);
			break;
		
		case Is :
			processToken(BinaryOp.Identical);
			break;
		
		case In :
			processToken(BinaryOp.In);
			break;
		
		case Bang :
			trange.popFront();
			switch(trange.front.type) {
				case Is :
					processToken(BinaryOp.NotIdentical);
					break;
				
				case In :
					processToken(BinaryOp.NotIn);
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
AstExpression parseShiftExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseShiftExpression(trange.parsePrefixExpression());
}

AstExpression parseShiftExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	lhs = trange.parseAddExpression(lhs);
	Location location = lhs.location;
	
	while(1) {
		void processToken(BinaryOp op) {
			trange.popFront();
			
			auto rhs = trange.parseAddExpression();
			
			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}
		
		switch(trange.front.type) with(TokenType) {
			case DoubleLess :
				processToken(BinaryOp.LeftShift);
				break;
			
			case DoubleMore :
				processToken(BinaryOp.SignedRightShift);
				break;
			
			case TripleMore :
				processToken(BinaryOp.UnsignedRightShift);
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
AstExpression parseAddExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseAddExpression(trange.parsePrefixExpression());
}

AstExpression parseAddExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	lhs = trange.parseMulExpression(lhs);
	Location location = lhs.location;
	
	while(1) {
		void processToken(BinaryOp op) {
			trange.popFront();
			
			auto rhs = trange.parseMulExpression();
			
			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}
		
		switch(trange.front.type) with(TokenType) {
			case Plus :
				processToken(BinaryOp.Add);
				break;
			
			case Minus :
				processToken(BinaryOp.Sub);
				break;
			
			case Tilde :
				processToken(BinaryOp.Concat);
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
AstExpression parseMulExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseMulExpression(trange.parsePrefixExpression());
}

AstExpression parseMulExpression(R)(ref R trange, AstExpression lhs) if(isTokenRange!R) {
	Location location = lhs.location;
	
	while(1) {
		void processToken(BinaryOp op) {
			trange.popFront();
			
			auto rhs = trange.parsePrefixExpression();
			
			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}
		
		switch(trange.front.type) with(TokenType) {
			case Star :
				processToken(BinaryOp.Mul);
				break;
			
			case Slash :
				processToken(BinaryOp.Div);
				break;
			
			case Percent :
				processToken(BinaryOp.Mod);
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Unary prefixes
 */
private AstExpression parsePrefixExpression(ParseMode mode = ParseMode.Greedy, R)(ref R trange) {
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
		
		case DoublePlus :
			processToken(UnaryOp.PreInc);
			break;
		
		case DoubleMinus :
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

AstExpression parsePrimaryExpression(R)(ref R trange) if(isTokenRange!R) {
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
			
			return new d.ir.expression.CharacterLiteral(location, str, TypeKind.Char);
		
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
			auto block = trange.parseBlock();
			
			return new DelegateLiteral(block);
		
		case Function :
		case Delegate :
			assert(0, "not implemented");
		
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
				
				alias typeof(parsed) caseType;
				
				import d.ast.type;
				static if(is(caseType : QualAstType)) {
					return new AstStaticTypeidExpression(location, parsed);
				} else static if(is(caseType : AstExpression)) {
					return new AstTypeidExpression(location, parsed);
				} else {
					return new IdentifierTypeidExpression(location, parsed);
				}
			})();
		
		case Is :
			return trange.parseIsExpression();
		
		case Assert :
			trange.popFront();
			trange.match(OpenParen);
			
			auto condition = trange.parseAssignExpression();
			AstExpression message;
			if(trange.front.type == Comma) {
				trange.popFront();
				message = trange.parseAssignExpression();
			}
			
			location.spanTo(trange.front.location);
			trange.match(CloseParen);
			
			return new AstAssertExpression(location, condition, message);
		
		case OpenParen :
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!OpenParen();
			
			trange.popFront();
			
			// TODO: (...)()
			if(matchingParen.front.type == Dot) {
				return trange.parseAmbiguous!((parsed) {
					trange.match(CloseParen);
					trange.match(Dot);
					
					return trange.parseIdentifierExpression(trange.parseQualifiedIdentifier(location, parsed));
				})();
			} else {
				auto expression = trange.parseExpression();
				
				location.spanTo(trange.front.location);
				trange.match(CloseParen);
				
				return new ParenExpression(location, expression);
			}
		
		default:
			// Our last resort are type.identifier expressions.
			auto type = trange.parseType!(ParseMode.Reluctant)();
			trange.match(Dot);
			
			return trange.parseIdentifierExpression(trange.parseQualifiedIdentifier(location, type));
	}
}

/**
 * Parse postfix ++, --, (...), [...], .identifier
 */
AstExpression parsePostfixExpression(ParseMode mode, R)(ref R trange, AstExpression e) if(isTokenRange!R) {
	Location location = e.location;
	
	while(1) {
		switch(trange.front.type) with(TokenType) {
			case DoublePlus :
				location.spanTo(trange.front.location);
				trange.popFront();
				
				e = new AstUnaryExpression(location, UnaryOp.PostInc, e);
				break;
			
			case DoubleMinus :
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
				
				if(trange.front.type == CloseBracket) {
					// We have a slicing operation here.
					assert(0, "Not implemented");
				} else {
					auto args = trange.parseArguments();
					switch(trange.front.type) {
						case CloseBracket :
							location.spanTo(trange.front.location);
							e = new AstIndexExpression(location, e, args);
							
							break;
						
						case DoubleDot :
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
			case TokenType.Dot :
				trange.popFront();
				
				e = trange.parseIdentifierExpression(trange.parseQualifiedIdentifier(location, e));
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
private AstExpression parsePowExpression(R)(ref R trange, AstExpression expr) {
	Location location = expr.location;
	
	while (trange.front.type == TokenType.DoubleCaret) {
		trange.popFront();
		AstExpression power = trange.parsePrefixExpression();
		location.spanTo(power.location);
		expr = new AstBinaryExpression(location, BinaryOp.Pow, expr, power);
	}
	
	return expr;
}

/**
 * Parse unary is expression.
 */
private auto parseIsExpression(R)(ref R trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Is);
	trange.match(TokenType.OpenParen);
	
	auto type = trange.parseType();
	
	// Handle alias throw is expression.
	if(trange.front.type == TokenType.Identifier) trange.popFront();
	
	switch(trange.front.type) with(TokenType) {
		case Colon :
			trange.popFront();
			trange.parseType();
			break;
		
		case DoubleAssign :
			trange.popFront();
			
			switch(trange.front.type) {
				case Struct, Union, Class, Interface, Enum, Function, Delegate, Super, Const, Immutable, Inout, Shared, Return, Typedef :
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
AstExpression parseIdentifierExpression(R)(ref R trange, Identifier i) if(isTokenRange!R) {
	if(trange.front.type != TokenType.OpenParen) {
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
AstExpression[] parseArguments(TokenType openTokenType, R)(ref R trange) if(isTokenRange!R) {
	alias closeTokenType = MatchingDelimiter!openTokenType;
	
	trange.match(openTokenType);
	
	if(trange.front.type == closeTokenType) {
		trange.match(closeTokenType);
		return [];
	}
	
	AstExpression[] args = [trange.parseAssignExpression()];
	
	while(trange.front.type == TokenType.Comma) {
		trange.popFront();
		
		args ~= trange.parseAssignExpression();
	}
	
	trange.match(closeTokenType);
	return args;
}

AstExpression[] parseArguments(R)(ref R trange) if(isTokenRange!R) {
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
private AstExpression parseIntegerLiteral(R)(ref R trange) {
	Location location = trange.front.location;
	
	auto value = trange.front.name.toString(trange.context);
	assert(value.length > 0);
	
	trange.match(TokenType.IntegerLiteral);
	
	bool isUnsigned, isLong;
	switch(value[$ - 1]) {
		case 'u', 'U' :
			assert(value.length > 1);
			isUnsigned = true;
			
			auto penultimo = value[$ - 2];
			if(penultimo == 'l' || penultimo == 'L') {
				isLong = true;
				value = value[0 .. $ - 2];
			} else {
				value = value[0 .. $ - 1];
			}
			
			break;
		
		case 'l', 'L' :
			assert(value.length > 1);
			isLong = true;
			
			auto penultimo = value[$ - 2];
			if(penultimo == 'u' || penultimo == 'U') {
				isUnsigned = true;
				value = value[0 .. $ - 2];
			} else {
				value = value[0 .. $ - 1];
			}
			
			break;
		
		default :
			break;
	}
	
	auto parse(Type)(string input) in {
		assert(input.length > 0);
	} body {
		import std.conv;
		if(value.length < 2) {
			return to!Type(value);
		}
		
		switch(value[0 .. 2]) {
			case "0x", "0X" :
				return to!Type(value[2 .. $], 16);
			
			case "0b", "0B" :
				return to!Type(value[2 .. $], 2);
			
			default :
				return to!Type(value);
		}
	}
	
	if(isUnsigned) {
		auto integer = parse!ulong(value);
		
		if(isLong || integer > uint.max) {
			return new IntegerLiteral!false(location, integer, TypeKind.Ulong);
		} else {
			return new IntegerLiteral!false(location, integer, TypeKind.Uint);
		}
	} else {
		auto integer = parse!long(value);
		
		if(isLong || integer > int.max || integer < int.min) {
			return new IntegerLiteral!true(location, integer, TypeKind.Long);
		} else {
			return new IntegerLiteral!true(location, integer, TypeKind.Int);
		}
	}
}

