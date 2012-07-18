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
			processToken!(OpAssignBinaryExpression!(BinaryOperation.AddAssign))();
			break;
		
		case TokenType.DashAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.SubAssign))();
			break;
		
		case TokenType.AsterixAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.MulAssign))();
			break;
		
		case TokenType.SlashAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.DivAssign))();
			break;
		
		case TokenType.PercentAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.ModAssign))();
			break;
		
		case TokenType.AmpersandAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.AndAssign))();
			break;
		
		case TokenType.PipeAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.OrAssign))();
			break;
		
		case TokenType.CaretAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.XorAssign))();
			break;
		
		case TokenType.TildeAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.CatAssign))();
			break;
		
		case TokenType.DoubleLessAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.ShiftLeftAssign))();
			break;
		
		case TokenType.DoubleGreaterAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.SignedShiftRightAssign))();
			break;
		
		case TokenType.TripleGreaterAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.UnsignedShiftRightAssign))();
			break;
		
		case TokenType.DoubleCaretAssign :
			processToken!(OpAssignBinaryExpression!(BinaryOperation.PowAssign))();
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
	return trange.parseBinaryExpression!(TokenType.DoublePipe, LogicalBinaryExpression!(BinaryOperation.LogicalOr), function Expression(ref TokenRange trange) { return trange.parseLogicalAndExpression(); })();
}

/**
 * Parse &&
 */
private auto parseLogicalAndExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.DoubleAmpersand, LogicalBinaryExpression!(BinaryOperation.LogicalAnd), function Expression(ref TokenRange trange) { return trange.parseBitwiseOrExpression(); })();
}

/**
 * Parse |
 */
private auto parseBitwiseOrExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.Pipe, BitwiseBinaryExpression!(BinaryOperation.BitwiseOr), function Expression(ref TokenRange trange) { return trange.parseBitwiseXorExpression(); })();
}

/**
 * Parse ^
 */
private auto parseBitwiseXorExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.Caret, BitwiseBinaryExpression!(BinaryOperation.BitwiseXor), function Expression(ref TokenRange trange) { return trange.parseBitwiseAndExpression(); })();
}

/**
 * Parse &
 */
private auto parseBitwiseAndExpression(TokenRange)(ref TokenRange trange) {
	return trange.parseBinaryExpression!(TokenType.Ampersand, BitwiseBinaryExpression!(BinaryOperation.BitwiseAnd), function Expression(ref TokenRange trange) { return trange.parseComparaisonExpression(); })();
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
			processToken!(EqualityExpression!(BinaryOperation.Equality))();
			break;
		
		case TokenType.BangAssign :
			processToken!(EqualityExpression!(BinaryOperation.NotEquality))();
			break;
		
		case TokenType.Less :
			processToken!(ComparaisonExpression!(BinaryOperation.Less))();
			break;
		
		case TokenType.LessAssign :
			processToken!(ComparaisonExpression!(BinaryOperation.LessEqual))();
			break;
		
		case TokenType.Greater:
			processToken!(ComparaisonExpression!(BinaryOperation.Greater))();
			break;
		
		case TokenType.GreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.GreaterEqual))();
			break;
		
		case TokenType.BangLessGreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.Unordered))();
			break;
		
		case TokenType.BangLessGreater:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedEqual))();
			break;
		
		case TokenType.LessGreater:
			processToken!(ComparaisonExpression!(BinaryOperation.LessGreater))();
			break;
		
		case TokenType.LessGreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.LessEqualGreater))();
			break;
		
		case TokenType.BangGreater:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedLessEqual))();
			break;
		
		case TokenType.BangGreaterAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedLess))();
			break;
		
		case TokenType.BangLess:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedGreaterEqual))();
			break;
		
		case TokenType.BangLessAssign:
			processToken!(ComparaisonExpression!(BinaryOperation.UnorderedGreater))();
			break;
		
		case TokenType.Is :
			processToken!(IdentityExpression!(BinaryOperation.Is))();
			break;
		
		case TokenType.In :
			processToken!(InExpression!(BinaryOperation.In))();
			break;
		
		case TokenType.Bang :
			trange.popFront();
			switch(trange.front.type) {
				case TokenType.Is :
					processToken!(IdentityExpression!(BinaryOperation.NotIs))();
					break;
				
				case TokenType.In :
					processToken!(InExpression!(BinaryOperation.NotIn))();
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
				processToken!(ShiftExpression!(BinaryOperation.LeftShift))();
				break;
			
			case TokenType.DoubleGreater :
				processToken!(ShiftExpression!(BinaryOperation.SignedRightShift))();
				break;
			
			case TokenType.TripleGreater :
				processToken!(ShiftExpression!(BinaryOperation.UnsignedRightShift))();
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
				processToken!AdditionExpression();
				break;
			
			case TokenType.Dash :
				processToken!SubstractionExpression();
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
				processToken!MultiplicationExpression();
				break;
			
			case TokenType.Slash :
				processToken!DivisionExpression();
				break;
			
			case TokenType.Percent :
				processToken!ModulusExpression();
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
			processToken!(OpAssignUnaryExpression!(UnaryPrefix.PrefixInc))();
			break;
		
		case TokenType.DoubleDash :
			processToken!(OpAssignUnaryExpression!(UnaryPrefix.PrefixDec))();
			break;
		
		case TokenType.Asterix :
			processToken!DereferenceExpression();
			break;
		
		case TokenType.Plus :
			processToken!(OperationUnaryExpression!(UnaryPrefix.UnaryPlus))();
			break;
		
		case TokenType.Dash :
			processToken!(OperationUnaryExpression!(UnaryPrefix.UnaryMinus))();
			break;
		
		case TokenType.Bang :
			processToken!NotExpression();
			break;
		
		case TokenType.Tilde :
			processToken!CompelementExpression();
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
					parseCast!CastExpression(null);
					break;
				
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

private Expression parsePrimaryExpression(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	switch(trange.front.type) {
		// Identified expressions
		case TokenType.Identifier :
			auto identifier = trange.parseIdentifier();
			location.spanTo(identifier.location);
			
			return new IdentifierExpression(location, identifier);
		
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
			auto identifier = trange.parseDotIdentifier();
			location.spanTo(identifier.location);
			
			return new IdentifierExpression(location, identifier);
		
		case TokenType.This :
			trange.popFront();
			return new ThisExpression(location);
		
		case TokenType.Super :
			trange.popFront();
			return new SuperExpression(location);
		
		case TokenType.True :
			trange.popFront();
			return new BooleanLiteral!true(location);
		
		case TokenType.False :
			trange.popFront();
			return new BooleanLiteral!false(location);
		
		case TokenType.Null :
			trange.popFront();
			return new NullLiteral(location);
		
		case TokenType.IntegerLiteral :
			return trange.parseIntegerLiteral();
		
		case TokenType.StringLiteral :
			string value = extractStringLiteral(trange.front.value);
			trange.popFront();
			
			return new StringLiteral(location, value);
		
		case TokenType.CharacterLiteral :
			string value = extractCharacterLiteral(trange.front.value);
			trange.popFront();
			
			return new CharacterLiteral(location, value);
		
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
			trange.popFront();
			
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!(TokenType.OpenParen)();
			
			Expression expression;
			if(matchingParen.front.type == TokenType.Dot) {
				import d.ast.identifier;
				
				Namespace qualifier = trange.parseTypeOrExpression!(delegate Namespace(parsed) {
					return parsed;
				})(matchingParen - trange - 1);
				
				trange.match(TokenType.CloseParen);
				trange.match(TokenType.Dot);
				
				auto identifier = trange.parseQualifiedIdentifier(location, qualifier);
				location.spanTo(identifier.location);
				
				expression = new IdentifierExpression(location, identifier);
			} else {
				expression = trange.parseExpression();
				trange.match(TokenType.CloseParen);
			}
			
			return expression;
		
		default:
			// Our last resort are type.identifier expressions.
			if(trange.getConfirmedType()) {
				auto type = trange.parseConfirmedType();
				trange.match(TokenType.Dot);
				
				auto identifier = trange.parseQualifiedIdentifier(location, type);
				location.spanTo(identifier.location);
				
				return new IdentifierExpression(location, identifier);
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
				processToken!(OpAssignUnaryExpression!(PostfixType.PostfixInc))();
				break;
			
			case TokenType.DoubleDash :
				processToken!(OpAssignUnaryExpression!(PostfixType.PostfixDec))();
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
				auto identifier = trange.parseQualifiedIdentifier(location, expression);
				location.spanTo(identifier.location);
				
				expression = new IdentifierExpression(location, identifier);
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
private PrimaryExpression parseIntegerLiteral(TokenRange)(ref TokenRange trange) {
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
			return new IntegerLiteral!ulong(location, integer);
		} else {
			return new IntegerLiteral!uint(location, cast(uint) integer);
		}
	} else {
		auto integer = parse!long(value);
		
		if(isLong || integer > int.max || integer < int.min) {
			return new IntegerLiteral!long(location, integer);
		} else {
			return new IntegerLiteral!int(location, cast(int) integer);
		}
	}
}

string extractStringLiteral(string value) {
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
			return extractString(Location.init, value[1..$]);
		
		case 'x':
			throw new CompilerPanic(Location.init, "hex literals are unimplemented.");
		
		default:
			throw new CompilerError(Location.init, format("unrecognised string prefix '%s'.", value[0]));
	}
}

string extractCharacterLiteral(string value) {
	return value[1 .. $ - 1];
}

