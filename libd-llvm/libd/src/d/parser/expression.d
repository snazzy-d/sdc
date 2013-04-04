module d.parser.expression;

import d.ast.expression;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.identifier;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

/**
 * Parse Expression
 */
Expression parseExpression(ParseMode mode = ParseMode.Greedy, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto lhs = trange.parsePrefixExpression!mode();
	return trange.parseBinaryExpression!(
		TokenType.Comma,
		CommaExpression,
		function Expression(ref TokenRange trange, Expression e) {
			return trange.parseAssignExpression(e);
		}
	)(lhs);
}

/**
 * Template used to parse basic BinaryExpressions.
 */
private Expression parseBinaryExpression(TokenType tokenType, BinaryExpressionType, alias parseNext, TokenRange)(ref TokenRange trange, Expression lhs) {
	lhs = parseNext(trange, lhs);
	Location location = lhs.location;
	
	while(trange.front.type == tokenType) {
		trange.popFront();
		
		auto rhs = trange.parsePrefixExpression();
		rhs = parseNext(trange, rhs);
		
		location.spanTo(rhs.location);
		
		lhs = new BinaryExpressionType(location, lhs, rhs);
	}
	
	return lhs;
}

/**
 * Parse assignement expressions.
 */
Expression parseAssignExpression(R)(ref R trange) if(isTokenRange!R) {
	return trange.parseAssignExpression(trange.parsePrefixExpression());
}

Expression parseAssignExpression(R)(ref R trange, Expression lhs) if(isTokenRange!R) {
	lhs = trange.parseConditionalExpression(lhs);
	Location location = lhs.location;
	
	void processToken(AssignExpressionType)() {
		trange.popFront();
		
		auto rhs = trange.parsePrefixExpression();
		rhs = trange.parseAssignExpression(rhs);
		
		location.spanTo(rhs.location);
		
		lhs = new AssignExpressionType(location, lhs, rhs);
	}
	
	switch(trange.front.type) with(TokenType) {
		case Assign :
			processToken!AssignExpression();
			break;
		
		case PlusAssign :
			processToken!AddAssignExpression();
			break;
		
		case MinusAssign :
			processToken!SubAssignExpression();
			break;
		
		case StarAssign :
			processToken!MulAssignExpression();
			break;
		
		case SlashAssign :
			processToken!DivAssignExpression();
			break;
		
		case PercentAssign :
			processToken!ModAssignExpression();
			break;
		
		case AmpersandAssign :
			processToken!BitwiseAndAssignExpression();
			break;
		
		case PipeAssign :
			processToken!BitwiseOrAssignExpression();
			break;
		
		case CaretAssign :
			processToken!BitwiseXorAssignExpression();
			break;
		
		case TildeAssign :
			processToken!ConcatAssignExpression();
			break;
		
		case DoubleLessAssign :
			processToken!LeftShiftAssignExpression();
			break;
		
		case DoubleMoreAssign :
			processToken!SignedRightShiftAssignExpression();
			break;
		
		case TripleMoreAssign :
			processToken!UnsignedRightShiftAssignExpression();
			break;
		
		case DoubleCaretAssign :
			processToken!PowAssignExpression();
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
private Expression parseConditionalExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseConditionalExpression(trange.parsePrefixExpression());
}

private Expression parseConditionalExpression(TokenRange)(ref TokenRange trange, Expression condition) {
	condition = trange.parseLogicalOrExpression(condition);
	
	if(trange.front.type == TokenType.QuestionMark) {
		Location location = condition.location;
		
		trange.popFront();
		auto ifTrue = trange.parseExpression();
		
		trange.match(TokenType.Colon);
		auto ifFalse = trange.parseConditionalExpression();
		
		location.spanTo(ifFalse.location);
		return new ConditionalExpression(location, condition, ifTrue, ifFalse);
	}
	
	return condition;
}

/**
 * Parse ||
 */
private Expression parseLogicalOrExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseLogicalOrExpression(trange.parsePrefixExpression());
}

private auto parseLogicalOrExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	return trange.parseBinaryExpression!(
		TokenType.DoublePipe,
		LogicalOrExpression,
		function Expression(ref TokenRange trange, Expression e) {
			return trange.parseLogicalAndExpression(e);
		}
	)(lhs);
}

/**
 * Parse &&
 */
private Expression parseLogicalAndExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseLogicalAndExpression(trange.parsePrefixExpression());
}

private auto parseLogicalAndExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	return trange.parseBinaryExpression!(
		TokenType.DoubleAmpersand,
		LogicalAndExpression,
		function Expression(ref TokenRange trange, Expression e) {
			return trange.parseBitwiseOrExpression(e);
		}
	)(lhs);
}

/**
 * Parse |
 */
private Expression parseBitwiseOrExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBitwiseOrExpression(trange.parsePrefixExpression());
}

private auto parseBitwiseOrExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	return trange.parseBinaryExpression!(
		TokenType.Pipe,
		BitwiseOrExpression,
		function Expression(ref TokenRange trange, Expression e) {
			return trange.parseBitwiseXorExpression(e);
		}
	)(lhs);
}

/**
 * Parse ^
 */
private Expression parseBitwiseXorExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBitwiseXorExpression(trange.parsePrefixExpression());
}

private auto parseBitwiseXorExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	return trange.parseBinaryExpression!(
		TokenType.Caret,
		BitwiseXorExpression,
		function Expression(ref TokenRange trange, Expression e) {
			return trange.parseBitwiseAndExpression(e);
		}
	)(lhs);
}

/**
 * Parse &
 */
private Expression parseBitwiseAndExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBitwiseAndExpression(trange.parsePrefixExpression());
}

private auto parseBitwiseAndExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	return trange.parseBinaryExpression!(
		TokenType.Ampersand,
		BitwiseAndExpression,
		function Expression(ref TokenRange trange, Expression e) {
			return trange.parseComparaisonExpression(e);
		}
	)(lhs);
}

/**
 * Parse ==, != and comparaisons
 */
private Expression parseComparaisonExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseComparaisonExpression(trange.parsePrefixExpression());
}

private Expression parseComparaisonExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	lhs = trange.parseShiftExpression(lhs);
	Location location = lhs.location;
	
	void processToken(BinaryExpressionType)() {
		trange.popFront();
		
		auto rhs = trange.parseShiftExpression();
		
		location.spanTo(rhs.location);
		lhs = new BinaryExpressionType(location, lhs, rhs);
	}
	
	switch(trange.front.type) {
		case TokenType.DoubleAssign :
			processToken!EqualityExpression();
			break;
		
		case TokenType.BangAssign :
			processToken!NotEqualityExpression();
			break;
		
		case TokenType.More:
			processToken!GreaterExpression();
			break;
		
		case TokenType.MoreAssign:
			processToken!GreaterEqualExpression();
			break;
		
		case TokenType.Less :
			processToken!LessExpression();
			break;
		
		case TokenType.LessAssign :
			processToken!LessEqualExpression();
			break;
		
		case TokenType.BangLessMoreAssign:
			processToken!UnorderedExpression();
			break;
		
		case TokenType.BangLessMore:
			processToken!UnorderedEqualExpression();
			break;
		
		case TokenType.LessMore:
			processToken!LessGreaterExpression();
			break;
		
		case TokenType.LessMoreAssign:
			processToken!LessEqualGreaterExpression();
			break;
		
		case TokenType.BangMore:
			processToken!UnorderedLessEqualExpression();
			break;
		
		case TokenType.BangMoreAssign:
			processToken!UnorderedLessExpression();
			break;
		
		case TokenType.BangLess:
			processToken!UnorderedGreaterEqualExpression();
			break;
		
		case TokenType.BangLessAssign:
			processToken!UnorderedGreaterExpression();
			break;
		
		case TokenType.Is :
			processToken!IdentityExpression();
			break;
		
		case TokenType.In :
			processToken!InExpression();
			break;
		
		case TokenType.Bang :
			trange.popFront();
			switch(trange.front.type) {
				case TokenType.Is :
					processToken!NotIdentityExpression();
					break;
				
				case TokenType.In :
					processToken!NotInExpression();
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
private Expression parseShiftExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseShiftExpression(trange.parsePrefixExpression());
}

private Expression parseShiftExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	lhs = trange.parseAddExpression(lhs);
	Location location = lhs.location;
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			trange.popFront();
			
			auto rhs = trange.parseAddExpression();
			
			location.spanTo(rhs.location);
			lhs = new BinaryExpressionType(location, lhs, rhs);
		}
		
		switch(trange.front.type) {
			case TokenType.DoubleLess :
				processToken!LeftShiftExpression();
				break;
			
			case TokenType.DoubleMore :
				processToken!SignedRightShiftExpression();
				break;
			
			case TokenType.TripleMore :
				processToken!UnsignedRightShiftExpression();
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Parse +, - and ~
 */
private Expression parseAddExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseAddExpression(trange.parsePrefixExpression());
}

private Expression parseAddExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	lhs = trange.parseMulExpression(lhs);
	Location location = lhs.location;
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			trange.popFront();
			
			auto rhs = trange.parseMulExpression();
			
			location.spanTo(rhs.location);
			lhs = new BinaryExpressionType(location, lhs, rhs);
		}
		
		switch(trange.front.type) {
			case TokenType.Plus :
				processToken!AddExpression();
				break;
			
			case TokenType.Minus :
				processToken!SubExpression();
				break;
			
			case TokenType.Tilde :
				processToken!ConcatExpression();
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Parse *, / and %
 */
private Expression parseMulExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseMulExpression(trange.parsePrefixExpression());
}

private Expression parseMulExpression(TokenRange)(ref TokenRange trange, Expression lhs) {
	Location location = lhs.location;
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			trange.popFront();
			
			auto rhs = trange.parsePrefixExpression();
			
			location.spanTo(rhs.location);
			lhs = new BinaryExpressionType(location, lhs, rhs);
		}
		
		switch(trange.front.type) {
			case TokenType.Star :
				processToken!MulExpression();
				break;
			
			case TokenType.Slash :
				processToken!DivExpression();
				break;
			
			case TokenType.Percent :
				processToken!ModExpression();
				break;
			
			default :
				return lhs;
		}
	}
}

/**
 * Unary prefixes
 */
private Expression parsePrefixExpression(ParseMode mode = ParseMode.Greedy, TokenRange)(ref TokenRange trange) {
	Expression result;
	
	void processToken(PrefixExpressionType)() {
		Location location = trange.front.location;
		
		trange.popFront();
		
		// Drop mode on purpose.
		result = trange.parsePrefixExpression();
		
		location.spanTo(result.location);
		result = new PrefixExpressionType(location, result);
	}
	
	switch(trange.front.type) {
		case TokenType.Ampersand :
			processToken!AddressOfExpression();
			break;
		
		case TokenType.DoublePlus :
			processToken!PreIncrementExpression();
			break;
		
		case TokenType.DoubleMinus :
			processToken!PreDecrementExpression();
			break;
		
		case TokenType.Star :
			processToken!DereferenceExpression();
			break;
		
		case TokenType.Plus :
			processToken!UnaryPlusExpression();
			break;
		
		case TokenType.Minus :
			processToken!UnaryMinusExpression();
			break;
		
		case TokenType.Bang :
			processToken!NotExpression();
			break;
		
		case TokenType.Tilde :
			processToken!ComplementExpression();
			break;
		
		// TODO: parse qualifier casts.
		case TokenType.Cast :
			Location location = trange.front.location;
			trange.popFront();
			trange.match(TokenType.OpenParen);
			
			auto parseCast(CastType, U...)(U params) {
				trange.match(TokenType.CloseParen);
				
				result = trange.parsePrefixExpression();
				location.spanTo(result.location);
				
				result = new CastType(location, params, result);
			}
			
			switch(trange.front.type) {
				case TokenType.CloseParen :
					assert(0, "cast() isn't supported.");
				
				default :
					auto type = trange.parseType();
					parseCast!CastExpression(type);
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

Expression parsePrimaryExpression(R)(ref R trange) if(isTokenRange!R) {
	Location location = trange.front.location;
	
	switch(trange.front.type) with(TokenType) {
		// Identified expressions
		case Identifier :
			return new IdentifierExpression(trange.parseIdentifier());
		
		case New :
			trange.popFront();
			auto type = trange.parseType();
			
			Expression[] arguments;
			if(trange.front.type == OpenParen) {
				trange.popFront();
				
				if(trange.front.type != CloseParen) {
					arguments = trange.parseArguments();
				}
				
				location.spanTo(trange.front.location);
				trange.match(CloseParen);
			} else {
				location.spanTo(type.location);
			}
			
			return new NewExpression(location, type, arguments);
		
		case Dot :
			return new IdentifierExpression(trange.parseDotIdentifier());
		
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
			auto str = trange.front.value;
			trange.popFront();
			
			return new d.ast.expression.StringLiteral(location, str);
		
		case CharacterLiteral :
			assert(trange.front.value.length == 1);
			
			auto value = trange.front.value[0];
			trange.popFront();
			
			return makeLiteral(location, value);
		
		case OpenBracket :
			Expression[] keys, values;
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
			
			return new ArrayLiteral(location, values);
		
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
			trange.match(TokenType.OpenParen);
			
			return trange.parseAmbiguous!(delegate Expression(parsed) {
				location.spanTo(trange.front.location);
				trange.match(CloseParen);
				
				alias typeof(parsed) caseType;
				
				import d.ast.type;
				static if(is(caseType : Type)) {
					return new StaticTypeidExpression(location, parsed);
				} else static if(is(caseType : Expression)) {
					return new TypeidExpression(location, parsed);
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
			Expression message;
			if(trange.front.type == Comma) {
				trange.popFront();
				message = trange.parseAssignExpression();
			}
			
			location.spanTo(trange.front.location);
			trange.match(CloseParen);
			
			return new AssertExpression(location, condition, message);
		
		case OpenParen :
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!OpenParen();
			
			trange.popFront();
			
			if(matchingParen.front.type == Dot) {
				import d.ast.identifier;
				
				auto identifier = trange.parseAmbiguous!((parsed) {
					trange.match(CloseParen);
					trange.match(Dot);
					
					return trange.parseQualifiedIdentifier(location, parsed);
				})();
				
				return new IdentifierExpression(identifier);
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
			
			return new IdentifierExpression(trange.parseQualifiedIdentifier(location, type));
	}
}

/**
 * Parse postfix ++, --, (...), [...], .identifier
 */
Expression parsePostfixExpression(ParseMode mode, TokenRange)(ref TokenRange trange, Expression e) if(isTokenRange!TokenRange) {
	Location location = e.location;
	
	while(1) {
		switch(trange.front.type) {
			case TokenType.DoublePlus :
				location.spanTo(trange.front.location);
				trange.popFront();
				
				e = new PostIncrementExpression(location, e);
				break;
			
			case TokenType.DoubleMinus :
				location.spanTo(trange.front.location);
				trange.popFront();
				
				e = new PostDecrementExpression(location, e);
				
				break;
			
			case TokenType.OpenParen :
				trange.popFront();
				
				Expression[] arguments;
				if(trange.front.type != TokenType.CloseParen) {
					arguments = trange.parseArguments();
				}
				
				location.spanTo(trange.front.location);
				trange.match(TokenType.CloseParen);
				
				e = new CallExpression(location, e, arguments);
				
				break;
			
			// TODO: Indices, Slices.
			case TokenType.OpenBracket :
				trange.popFront();
				
				if(trange.front.type == TokenType.CloseBracket) {
					// We have a slicing operation here.
					assert(0, "Not implemented");
				} else {
					auto arguments = trange.parseArguments();
					switch(trange.front.type) {
						case TokenType.CloseBracket :
							location.spanTo(trange.front.location);
							e = new IndexExpression(location, e, arguments);
							
							break;
						
						case TokenType.DoubleDot :
							trange.popFront();
							auto second = trange.parseArguments();
							
							location.spanTo(trange.front.location);
							e = new SliceExpression(location, e, arguments, second);
							
							break;
						
						default :
							// TODO: error message that make sense.
							trange.match(TokenType.Begin);
							break;
					}
				}
				
				trange.match(TokenType.CloseBracket);
				
				break;
			
			static if(mode == ParseMode.Greedy) {
			case TokenType.Dot :
				trange.popFront();
				
				e = new IdentifierExpression(trange.parseQualifiedIdentifier(location, e));
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
private Expression parsePowExpression(TokenRange)(ref TokenRange trange, Expression expression) {
	Location location = expression.location;
	
	while (trange.front.type == TokenType.DoubleCaret) {
		trange.popFront();
		Expression power = trange.parsePrefixExpression();
		location.spanTo(power.location);
		expression = new PowExpression(location, expression, power);
	}
	
	return expression;
}

/**
 * Parse unary is expression.
 */
private auto parseIsExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Is);
	trange.match(TokenType.OpenParen);
	
	auto type = trange.parseType();
	
	// Handle alias throw is expression.
	if(trange.front.type == TokenType.Identifier) trange.popFront();
	
	switch(trange.front.type) {
		case TokenType.Colon :
			trange.popFront();
			trange.parseType();
			break;
		
		case TokenType.DoubleAssign :
			trange.popFront();
			
			switch(trange.front.type) {
				case TokenType.Struct, TokenType.Union, TokenType.Class, TokenType.Interface, TokenType.Enum, TokenType.Function, TokenType.Delegate, TokenType.Super, TokenType.Const, TokenType.Immutable, TokenType.Inout, TokenType.Shared, TokenType.Return, TokenType.Typedef :
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
 * Parse function arguments
 */
Expression[] parseArguments(R)(ref R trange) if(isTokenRange!R) {
	Expression[] expressions = [trange.parseAssignExpression()];
	
	while(trange.front.type == TokenType.Comma) {
		trange.popFront();
		
		expressions ~= trange.parseAssignExpression();
	}
	
	return expressions;
}

/**
 * Parse integer literals
 */
private Expression parseIntegerLiteral(R)(ref R trange) {
	Location location = trange.front.location;
	
	string value = trange.front.value;
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
			return makeLiteral(location, integer);
		} else {
			return makeLiteral(location, cast(uint) integer);
		}
	} else {
		auto integer = parse!long(value);
		
		if(isLong || integer > int.max || integer < int.min) {
			return makeLiteral(location, integer);
		} else {
			return makeLiteral(location, cast(int) integer);
		}
	}
}

