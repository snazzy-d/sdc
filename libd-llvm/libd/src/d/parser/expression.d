module d.parser.expression;

import d.ast.expression;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.identifier;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

/**
 * Template used to parse basic BinaryExpressions.
 */
private auto parseBinaryExpression(TokenType tokenType, BinaryExpressionType, alias parseNext, TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	Expression result = parseNext(trange);
	
	while(trange.front.type == tokenType) {
		trange.popFront();
		
		auto rhs = parseNext(trange);
		
		location.spanTo(rhs.location);
		
		result = new BinaryExpressionType(location, result, rhs);
	}
	
	return result;
}

/**
 * Parse Expression
 */
Expression parseExpression(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	return trange.parseBinaryExpression!(TokenType.Comma, CommaExpression, function Expression(ref TokenRange trange) { return trange.parseAssignExpression(); })();
}

/**
 * Parse assignement expressions.
 */
Expression parseAssignExpression(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	Expression result = trange.parseConditionalExpression();
	
	void processToken(AssignExpressionType)() {
		trange.popFront();
		
		auto value = trange.parseAssignExpression();
		
		location.spanTo(value.location);
		
		result = new AssignExpressionType(location, result, value);
	}
	
	switch(trange.front.type) {
		case TokenType.Assign :
			processToken!AssignExpression();
			break;
		
		case TokenType.PlusAssign :
			processToken!AddAssignExpression();
			break;
		
		case TokenType.DashAssign :
			processToken!SubAssignExpression();
			break;
		
		case TokenType.AsterixAssign :
			processToken!MulAssignExpression();
			break;
		
		case TokenType.SlashAssign :
			processToken!DivAssignExpression();
			break;
		
		case TokenType.PercentAssign :
			processToken!ModAssignExpression();
			break;
		
		case TokenType.AmpersandAssign :
			processToken!BitwiseAndAssignExpression();
			break;
		
		case TokenType.PipeAssign :
			processToken!BitwiseOrAssignExpression();
			break;
		
		case TokenType.CaretAssign :
			processToken!BitwiseXorAssignExpression();
			break;
		
		case TokenType.TildeAssign :
			processToken!ConcatAssignExpression();
			break;
		
		case TokenType.DoubleLessAssign :
			processToken!LeftShiftAssignExpression();
			break;
		
		case TokenType.DoubleGreaterAssign :
			processToken!SignedRightShiftAssignExpression();
			break;
		
		case TokenType.TripleGreaterAssign :
			processToken!UnsignedRightShiftAssignExpression();
			break;
		
		case TokenType.DoubleCaretAssign :
			processToken!PowAssignExpression();
			break;
		
		default :
			// No assignement.
			break;
	}
	
	return result;
}

/**
 * Parse ?:
 */
private Expression parseConditionalExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	Expression result = trange.parseLogicalOrExpression();
	
	if(trange.front.type == TokenType.QuestionMark) {
		trange.popFront();
		Expression ifTrue = trange.parseExpression();
		
		trange.match(TokenType.Colon);
		Expression ifFalse = trange.parseConditionalExpression();
		
		location.spanTo(ifFalse.location);
		result = new ConditionalExpression(location, result, ifTrue, ifFalse);
	}
	
	return result;
}

/**
 * Parse ||
 */
private auto parseLogicalOrExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.DoublePipe, LogicalOrExpression, function Expression(ref TokenRange trange) { return trange.parseLogicalAndExpression(); })();
}

/**
 * Parse &&
 */
private auto parseLogicalAndExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.DoubleAmpersand, LogicalAndExpression, function Expression(ref TokenRange trange) { return trange.parseBitwiseOrExpression(); })();
}

/**
 * Parse |
 */
private auto parseBitwiseOrExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.Pipe, BitwiseOrExpression, function Expression(ref TokenRange trange) { return trange.parseBitwiseXorExpression(); })();
}

/**
 * Parse ^
 */
private auto parseBitwiseXorExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.Caret, BitwiseXorExpression, function Expression(ref TokenRange trange) { return trange.parseBitwiseAndExpression(); })();
}

/**
 * Parse &
 */
private auto parseBitwiseAndExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.Ampersand, BitwiseAndExpression, function Expression(ref TokenRange trange) { return trange.parseComparaisonExpression(); })();
}

/**
 * Parse ==, != and comparaisons
 */
private auto parseComparaisonExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	Expression result = trange.parseShiftExpression();
	
	void processToken(BinaryExpressionType)() {
		trange.popFront();
		
		auto rhs = trange.parseShiftExpression();
		
		location.spanTo(rhs.location);
		
		result = new BinaryExpressionType(location, result, rhs);
	}
	
	switch(trange.front.type) {
		case TokenType.DoubleAssign :
			processToken!EqualityExpression();
			break;
		
		case TokenType.BangAssign :
			processToken!NotEqualityExpression();
			break;
		
		case TokenType.Greater:
			processToken!GreaterExpression();
			break;
		
		case TokenType.GreaterAssign:
			processToken!GreaterEqualExpression();
			break;
		
		case TokenType.Less :
			processToken!LessExpression();
			break;
		
		case TokenType.LessAssign :
			processToken!LessEqualExpression();
			break;
		
		case TokenType.BangLessGreaterAssign:
			processToken!UnorderedExpression();
			break;
		
		case TokenType.BangLessGreater:
			processToken!UnorderedEqualExpression();
			break;
		
		case TokenType.LessGreater:
			processToken!LessGreaterExpression();
			break;
		
		case TokenType.LessGreaterAssign:
			processToken!LessEqualGreaterExpression();
			break;
		
		case TokenType.BangGreater:
			processToken!UnorderedLessEqualExpression();
			break;
		
		case TokenType.BangGreaterAssign:
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
	
	return result;
}

/**
 * Parse <<, >> and >>>
 */
private auto parseShiftExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	Expression result = trange.parseAddExpression();
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			trange.popFront();
			
			auto rhs = trange.parseAddExpression();
			
			location.spanTo(rhs.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(trange.front.type) {
			case TokenType.DoubleLess :
				processToken!LeftShiftExpression();
				break;
			
			case TokenType.DoubleGreater :
				processToken!SignedRightShiftExpression();
				break;
			
			case TokenType.TripleGreater :
				processToken!UnsignedRightShiftExpression();
				break;
			
			default :
				return result;
		}
	}
}

/**
 * Parse +, - and ~
 */
private auto parseAddExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	Expression result = trange.parseMulExpression();
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			trange.popFront();
			
			auto rhs = trange.parseMulExpression();
			
			location.spanTo(rhs.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(trange.front.type) {
			case TokenType.Plus :
				processToken!AddExpression();
				break;
			
			case TokenType.Dash :
				processToken!SubExpression();
				break;
			
			case TokenType.Tilde :
				processToken!ConcatExpression();
				break;
			
			default :
				return result;
		}
	}
}

/**
 * Parse *, / and %
 */
private auto parseMulExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	Expression result = trange.parsePrefixExpression();
	
	while(1) {
		void processToken(BinaryExpressionType)() {
			trange.popFront();
			
			auto rhs = trange.parsePrefixExpression();
			
			location.spanTo(rhs.location);
			
			result = new BinaryExpressionType(location, result, rhs);
		}
		
		switch(trange.front.type) {
			case TokenType.Asterix :
				processToken!MulExpression();
				break;
			
			case TokenType.Slash :
				processToken!DivExpression();
				break;
			
			case TokenType.Percent :
				processToken!ModExpression();
				break;
			
			default :
				return result;
		}
	}
}

/**
 * Unary prefixes
 */
private Expression parsePrefixExpression(TokenRange)(ref TokenRange trange) {
	Expression result;
	
	void processToken(PrefixExpressionType)() {
		Location location = trange.front.location;
		
		trange.popFront();
		
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
		
		case TokenType.DoubleDash :
			processToken!PreDecrementExpression();
			break;
		
		case TokenType.Asterix :
			processToken!DereferenceExpression();
			break;
		
		case TokenType.Plus :
			processToken!UnaryPlusExpression();
			break;
		
		case TokenType.Dash :
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
			
			auto parseCast(CastType, U ...)(U params) {
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
		
		case TokenType.Delete :
			processToken!DeleteExpression();
			break;
		
		default :
			result = trange.parsePrimaryExpression();
			result = trange.parsePostfixExpression(result);
	}
	
	// Ensure we do not screwed up.
	assert(result);
	
	return trange.parsePowExpression(result);
}

Expression parsePrimaryExpression(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	switch(trange.front.type) {
		// Identified expressions
		case TokenType.Identifier :
			return new IdentifierExpression(trange.parseIdentifier());
		
		case TokenType.New :
			trange.popFront();
			auto type = trange.parseType();
			
			Expression[] arguments;
			if(trange.front.type == TokenType.OpenParen) {
				trange.popFront();
				arguments = trange.parseArguments();
				
				location.spanTo(trange.front.location);
				trange.match(TokenType.CloseParen);
			} else {
				location.spanTo(type.location);
			}
			
			return new NewExpression(location, type, arguments);
		
		case TokenType.Dot :
			return new IdentifierExpression(trange.parseDotIdentifier());
		
		case TokenType.This :
			trange.popFront();
			return new ThisExpression(location);
		
		case TokenType.Super :
			trange.popFront();
			return new SuperExpression(location);
		
		case TokenType.True :
			trange.popFront();
			return new BooleanLiteral(location, true);
		
		case TokenType.False :
			trange.popFront();
			return new BooleanLiteral(location, false);
		
		case TokenType.Null :
			trange.popFront();
			return new NullLiteral(location);
		
		case TokenType.IntegerLiteral :
			return trange.parseIntegerLiteral();
		
		case TokenType.StringLiteral :
			auto value = extractStringLiteral(trange.front.location, trange.front.value);
			trange.popFront();
			
			return new StringLiteral(location, value);
		
		case TokenType.CharacterLiteral :
			auto value = extractCharacterLiteral(trange.front.value);
			trange.popFront();
			
			return makeLiteral(location, value);
		
		case TokenType.OpenBracket :
			Expression[] keys, values;
			do {
				trange.popFront();
				auto value = trange.parseAssignExpression();
				
				if(trange.front.type == TokenType.Colon) {
					keys ~= value;
					trange.popFront();
					values ~= trange.parseAssignExpression();
				} else {
					values ~= value;
				}
			} while(trange.front.type == TokenType.Comma);
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.CloseBracket);
			
			return new ArrayLiteral(location, values);
		
		case TokenType.OpenBrace :
			auto block = trange.parseBlock();
			
			return new DelegateLiteral(block);
		
		case TokenType.__File__ :
			trange.popFront();
			return new __File__Literal(location);
		
		case TokenType.__Line__ :
			trange.popFront();
			return new __Line__Literal(location);
		
		case TokenType.Dollar :
			trange.popFront();
			return new DollarExpression(location);
		
		case TokenType.Typeid :
			trange.popFront();
			
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!(TokenType.OpenParen)();
			
			trange.match(TokenType.OpenParen);
			
			return trange.parseTypeOrExpression!(delegate Expression(parsed) {
				location.spanTo(trange.front.location);
				trange.match(TokenType.CloseParen);
				
				alias typeof(parsed) caseType;
				
				import d.ast.type;
				static if(is(caseType : Type)) {
					return new StaticTypeidExpression(location, parsed);
				} else static if(is(caseType : Expression)) {
					return new TypeidExpression(location, parsed);
				} else {
					return new AmbiguousTypeidExpression(location, parsed);
				}
			})(matchingParen - trange - 1);
		
		case TokenType.Is :
			return trange.parseIsExpression();
		
		case TokenType.Assert :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			
			auto arguments = trange.parseArguments();
			
			location.spanTo(trange.front.location);
			trange.match(TokenType.CloseParen);
			
			return new AssertExpression(location, arguments);
		
		case TokenType.OpenParen :
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!(TokenType.OpenParen)();
			
			trange.popFront();
			
			if(matchingParen.front.type == TokenType.Dot) {
				import d.ast.identifier;
				
				auto identifier = trange.parseTypeOrExpression!(delegate Identifier(parsed) {
					trange.match(TokenType.CloseParen);
					trange.match(TokenType.Dot);
					
					return trange.parseQualifiedIdentifier(location, parsed);
				})(matchingParen - trange - 1);
				
				return new IdentifierExpression(identifier);
			} else {
				auto expression = trange.parseExpression();
				
				location.spanTo(trange.front.location);
				trange.match(TokenType.CloseParen);
				
				return new ParenExpression(location, expression);
			}
		
		default:
			// Our last resort are type.identifier expressions.
			if(trange.getConfirmedType()) {
				auto type = trange.parseConfirmedType();
				trange.match(TokenType.Dot);
				
				return new IdentifierExpression(trange.parseQualifiedIdentifier(location, type));
			}
			
			trange.match(TokenType.Begin);
			assert(0);
	}
}

/**
 * Parse ^^
 */
private auto parsePowExpression(TokenRange)(ref TokenRange trange, Expression expression) {
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
 * Parse postfix ++, --, (...), [...], .identifier
 */
private Expression parsePostfixExpression(TokenRange)(ref TokenRange trange, Expression expression) {
	Location location = expression.location;
	
	while(1) {
		// TODO: refactor, it make no sense anymore.
		void processToken(PostfixExpressionType, TokenType endToken = TokenType.None)() {
			static if(endToken != TokenType.None) {
				trange.popFront();
				
				Expression[] arguments;
				
				if(trange.front.type != endToken) {
					arguments = trange.parseArguments();
				}
				
				location.spanTo(trange.front.location);
				trange.match(endToken);
				
				expression = new PostfixExpressionType(location, expression, arguments);
			} else {
				location.spanTo(trange.front.location);
				trange.popFront();
				
				expression = new PostfixExpressionType(location, expression);
			}
		}
		
		switch(trange.front.type) {
			case TokenType.DoublePlus :
				processToken!PostIncrementExpression();
				break;
			
			case TokenType.DoubleDash :
				processToken!PostDecrementExpression();
				break;
			
			case TokenType.OpenParen :
				processToken!(CallExpression, TokenType.CloseParen)();
				break;
			
			// TODO: Indices, Slices.
			case TokenType.OpenBracket :
				trange.popFront();
				
				if(trange.front.type == TokenType.CloseBracket) {
					// We have a slicing operation here.
				} else {
					auto arguments = trange.parseArguments();
					switch(trange.front.type) {
						case TokenType.CloseBracket :
							location.spanTo(trange.front.location);
							expression = new IndexExpression(location, expression, arguments);
							break;
					
						case TokenType.DoubleDot :
							trange.popFront();
							auto second = trange.parseArguments();
							break;
					
						default :
							// TODO: error message that make sense.
							trange.match(TokenType.Begin);
							break;
					}
				}
				
				trange.match(TokenType.CloseBracket);
				
				break;
			
			case TokenType.Dot :
				trange.popFront();
				
				expression = new IdentifierExpression(trange.parseQualifiedIdentifier(location, expression));
				break;
			
			default :
				return expression;
		}
	}
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
					trange.popFront();
					break;
				
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
auto parseArguments(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
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
private Expression parseIntegerLiteral(TokenRange)(ref TokenRange trange) {
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

string extractStringLiteral(Location location, string value) {
	// TODO: refactor this to not depend on SDC's internals.
	import sdc.extract;
	import sdc.compilererror;
	import std.string;
	
	switch(value[0]) {
		case 'r', 'q':
			return extractRawString(value[1..$]);
		
		case '`':
			return extractRawString(value);
		
		case '"':
			return extractString(location, value[1..$]);
		
		case 'x':
			throw new CompilerPanic(location, "hex literals are unimplemented.");
		
		default:
			throw new CompilerError(location, format("unrecognised string prefix '%s'.", value[0]));
	}
}

char extractCharacterLiteral(string value) {
	return value[1];
}

