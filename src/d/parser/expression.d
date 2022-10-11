module d.parser.expression;

import d.ast.expression;
import d.ast.identifier;

import d.ir.expression;

import d.parser.ambiguous;
import d.parser.base;
import d.parser.identifier;
import d.parser.statement;
import d.parser.type;
import source.parserutil;

/**
 * Parse Expression
 */
AstExpression parseExpression(ParseMode mode = ParseMode.Greedy)(
	ref TokenRange trange
) {
	auto lhs = trange.parsePrefixExpression!mode();
	return trange.parseAstBinaryExpression!(
		TokenType.Comma, AstBinaryOp.Comma,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseAssignExpression(e);
		})(lhs);
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

	switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
		case Equal:
			processToken(Assign);
			break;

		case PlusEqual:
			processToken(AddAssign);
			break;

		case MinusEqual:
			processToken(SubAssign);
			break;

		case StarEqual:
			processToken(MulAssign);
			break;

		case SlashEqual:
			processToken(DivAssign);
			break;

		case PercentEqual:
			processToken(RemAssign);
			break;

		case AmpersandEqual:
			processToken(AndAssign);
			break;

		case PipeEqual:
			processToken(OrAssign);
			break;

		case CaretEqual:
			processToken(XorAssign);
			break;

		case TildeEqual:
			processToken(ConcatAssign);
			break;

		case LessLessEqual:
			processToken(LeftShiftAssign);
			break;

		case MoreMoreEqual:
			processToken(SignedRightShiftAssign);
			break;

		case MoreMoreMoreEqual:
			processToken(UnsignedRightShiftAssign);
			break;

		case CaretCaretEqual:
			processToken(PowAssign);
			break;

		default:
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

AstExpression parseTernaryExpression(ref TokenRange trange,
                                     AstExpression condition) {
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
		TokenType.PipePipe, AstBinaryOp.LogicalOr,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseLogicalAndExpression(e);
		})(lhs);
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
		TokenType.AmpersandAmpersand, AstBinaryOp.LogicalAnd,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseBitwiseOrExpression(e);
		})(lhs);
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
		TokenType.Pipe, AstBinaryOp.Or,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseBitwiseXorExpression(e);
		})(lhs);
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
		TokenType.Caret, AstBinaryOp.Xor,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseBitwiseAndExpression(e);
		})(lhs);
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
		TokenType.Ampersand, AstBinaryOp.And,
		function AstExpression(ref TokenRange trange, AstExpression e) {
			return trange.parseComparaisonExpression(e);
		})(lhs);
}

/**
 * Parse ==, != and comparaisons
 */
// FIXME: Should be private, but dmd don't like that.
AstExpression parseComparaisonExpression(ref TokenRange trange) {
	return trange.parseComparaisonExpression(trange.parsePrefixExpression());
}

AstExpression parseComparaisonExpression(ref TokenRange trange,
                                         AstExpression lhs) {
	lhs = trange.parseShiftExpression(lhs);
	Location location = lhs.location;

	void processToken(AstBinaryOp op) {
		trange.popFront();

		auto rhs = trange.parseShiftExpression();

		location.spanTo(rhs.location);
		lhs = new AstBinaryExpression(location, op, lhs, rhs);
	}

	switch (trange.front.type) with (TokenType) {
		case EqualEqual:
			processToken(AstBinaryOp.Equal);
			break;

		case BangEqual:
			processToken(AstBinaryOp.NotEqual);
			break;

		case More:
			processToken(AstBinaryOp.Greater);
			break;

		case MoreEqual:
			processToken(AstBinaryOp.GreaterEqual);
			break;

		case Less:
			processToken(AstBinaryOp.Less);
			break;

		case LessEqual:
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

		case Is:
			processToken(AstBinaryOp.Identical);
			break;

		case In:
			processToken(AstBinaryOp.In);
			break;

		case Bang:
			trange.popFront();
			switch (trange.front.type) {
				case Is:
					processToken(AstBinaryOp.NotIdentical);
					break;

				case In:
					processToken(AstBinaryOp.NotIn);
					break;

				default:
					trange.match(TokenType.Begin);
					break;
			}

			break;

		default:
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

	while (true) {
		void processToken(AstBinaryOp op) {
			trange.popFront();

			auto rhs = trange.parseAddExpression();

			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}

		switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
			case LessLess:
				processToken(LeftShift);
				break;

			case MoreMore:
				processToken(SignedRightShift);
				break;

			case MoreMoreMore:
				processToken(UnsignedRightShift);
				break;

			default:
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

	while (true) {
		void processToken(AstBinaryOp op) {
			trange.popFront();

			auto rhs = trange.parseMulExpression();

			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}

		switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
			case Plus:
				processToken(Add);
				break;

			case Minus:
				processToken(Sub);
				break;

			case Tilde:
				processToken(Concat);
				break;

			default:
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

	while (true) {
		void processToken(AstBinaryOp op) {
			trange.popFront();

			auto rhs = trange.parsePrefixExpression();

			location.spanTo(rhs.location);
			lhs = new AstBinaryExpression(location, op, lhs, rhs);
		}

		switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
			case Star:
				processToken(Mul);
				break;

			case Slash:
				processToken(Div);
				break;

			case Percent:
				processToken(Rem);
				break;

			default:
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

	switch (trange.front.type) with (TokenType) {
		case Ampersand:
			processToken(UnaryOp.AddressOf);
			break;

		case PlusPlus:
			processToken(UnaryOp.PreInc);
			break;

		case MinusMinus:
			processToken(UnaryOp.PreDec);
			break;

		case Star:
			processToken(UnaryOp.Dereference);
			break;

		case Plus:
			processToken(UnaryOp.Plus);
			break;

		case Minus:
			processToken(UnaryOp.Minus);
			break;

		case Bang:
			processToken(UnaryOp.Not);
			break;

		case Tilde:
			processToken(UnaryOp.Complement);
			break;

		// TODO: parse qualifier casts.
		case Cast:
			Location location = trange.front.location;
			trange.popFront();
			trange.match(OpenParen);

			switch (trange.front.type) {
				case CloseParen:
					assert(0, "cast() isn't supported.");

				default:
					auto type = trange.parseType();
					trange.match(CloseParen);

					result = trange.parsePrefixExpression();
					location.spanTo(result.location);

					result = new AstCastExpression(location, type, result);
			}

			break;

		default:
			result = trange.parsePrimaryExpression();
			result = trange.parsePostfixExpression!mode(result);
	}

	// Ensure we do not screwed up.
	assert(result);

	return trange.parsePowExpression(result);
}

AstExpression parsePrimaryExpression(ref TokenRange trange) {
	Location location = trange.front.location;

	switch (trange.front.type) with (TokenType) {
		// Identified expressions
		case Identifier:
			return trange.parseIdentifierExpression(trange.parseIdentifier());

		case New:
			trange.popFront();
			auto type = trange.parseType();
			auto args = trange.parseArguments!OpenParen();

			location.spanTo(trange.front.location);
			return new AstNewExpression(location, type, args);

		case Dot:
			return
				trange.parseIdentifierExpression(trange.parseDotIdentifier());

		case This:
			trange.popFront();
			return new ThisExpression(location);

		case Super:
			trange.popFront();
			return new SuperExpression(location);

		case True:
			trange.popFront();
			return new BooleanLiteral(location, true);

		case False:
			trange.popFront();
			return new BooleanLiteral(location, false);

		case Null:
			trange.popFront();
			return new NullLiteral(location);

		case FloatLiteral:
			return trange.parseFloatLiteral();

		case IntegerLiteral:
			return trange.parseIntegerLiteral();

		case StringLiteral:
			return trange.parseStringLiteral();

		case CharacterLiteral:
			return trange.parseCharacterLiteral();

		case OpenBracket:
			// FIXME: Support map literals.
			AstExpression[] values;
			trange.popFront();

			while (trange.front.type != CloseBracket) {
				values ~= trange.parseAssignExpression();
				if (!trange.popOnMatch(TokenType.Comma)) {
					break;
				}
			}

			location.spanTo(trange.front.location);
			trange.match(CloseBracket);

			return new AstArrayLiteral(location, values);

		case OpenBrace:
			return new DelegateLiteral(trange.parseBlock());

		case Function, Delegate:
			assert(0, "Functions or Delegates not implemented ");

		case __File__:
			trange.popFront();
			return new __File__Literal(location);

		case __Line__:
			trange.popFront();
			return new __Line__Literal(location);

		case Dollar:
			trange.popFront();
			return new DollarExpression(location);

		case Typeid:
			trange.popFront();
			trange.match(OpenParen);

			return trange.parseAmbiguous!(delegate AstExpression(parsed) {
				location.spanTo(trange.front.location);
				trange.match(CloseParen);

				import d.ast.type;

				alias T = typeof(parsed);
				static if (is(T : AstType)) {
					return new AstStaticTypeidExpression(location, parsed);
				} else static if (is(T : AstExpression)) {
					return new AstTypeidExpression(location, parsed);
				} else {
					return new IdentifierTypeidExpression(location, parsed);
				}
			})();

		case Is:
			return trange.parseIsExpression();

		case Mixin:
			import d.parser.conditional;
			return trange.parseMixin!AstExpression();

		case OpenParen:
			auto matchingParen = trange.getLookahead();
			matchingParen.popMatchingDelimiter!OpenParen();

			switch (matchingParen.front.type) {
				case Dot:
					trange.popFront();
					return trange.parseAmbiguous!((parsed) {
						trange.match(CloseParen);
						trange.match(Dot);

						auto qi =
							trange.parseQualifiedIdentifier(location, parsed);
						return trange.parseIdentifierExpression(qi);
					})();

				case OpenBrace:
					import d.parser.declaration;
					bool isVariadic;
					auto params = trange.parseParameters(isVariadic);

					auto block = trange.parseBlock();
					location.spanTo(block.location);

					return new DelegateLiteral(location, params, isVariadic,
					                           block);

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
			switch (trange.front.type) {
				case Dot:
					trange.popFront();
					return trange.parseIdentifierExpression(
						trange.parseQualifiedIdentifier(location, type));

				case OpenParen:
					auto args = trange.parseArguments!OpenParen();
					location.spanTo(trange.previous);
					return new TypeCallExpression(location, type, args);

				default:
					break;
			}

			// TODO: error message that make sense.
			trange.match(Begin);
			assert(0, "Implement proper error handling :)");
	}
}

/**
 * Parse postfix ++, --, (...), [...], .identifier
 */
AstExpression parsePostfixExpression(ParseMode mode)(ref TokenRange trange,
                                                     AstExpression e) {
	Location location = e.location;

	while (true) {
		switch (trange.front.type) with (TokenType) {
			case PlusPlus:
				location.spanTo(trange.front.location);
				trange.popFront();

				e = new AstUnaryExpression(location, UnaryOp.PostInc, e);
				break;

			case MinusMinus:
				location.spanTo(trange.front.location);
				trange.popFront();

				e = new AstUnaryExpression(location, UnaryOp.PostDec, e);
				break;

			case OpenParen:
				auto args = trange.parseArguments!OpenParen();

				location.spanTo(trange.previous);
				e = new AstCallExpression(location, e, args);

				break;

			// TODO: Indices, Slices.
			case OpenBracket:
				trange.popFront();

				if (trange.front.type == CloseBracket) {
					// We have a slicing operation here.
					assert(0, "Slice expressions can not be parsed yet");
				} else {
					auto args = trange.parseArguments();
					switch (trange.front.type) {
						case CloseBracket:
							location.spanTo(trange.front.location);
							e = new AstIndexExpression(location, e, args);

							break;

						case DotDot:
							trange.popFront();
							auto second = trange.parseArguments();

							location.spanTo(trange.front.location);
							e = new AstSliceExpression(location, e, args,
							                           second);

							break;

						default:
							// TODO: error message that make sense.
							trange.match(Begin);
							break;
					}
				}

				trange.match(CloseBracket);
				break;

			static if (mode == ParseMode.Greedy) {
				case Dot:
					trange.popFront();

					e = trange.parseIdentifierExpression(
						trange.parseQualifiedIdentifier(location, e));

					break;
			}

			default:
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

	switch (trange.front.type) with (TokenType) {
		case Colon:
			trange.popFront();
			trange.parseType();
			break;

		case EqualEqual:
			trange.popFront();

			switch (trange.front.type) {
				case Struct, Union, Class, Interface, Enum, Function, Delegate:
				case Super, Const, Immutable, Inout, Shared, Return:
					assert(0, "Not implemented.");

				default:
					trange.parseType();
			}

			break;

		default:
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
	location.spanTo(trange.previous);
	return new IdentifierCallExpression(location, i, args);
}

/**
 * Parse function arguments
 */
AstExpression[] parseArguments(TokenType openTokenType)(ref TokenRange trange) {
	alias closeTokenType = MatchingDelimiter!openTokenType;

	trange.match(openTokenType);

	AstExpression[] args;
	while (trange.front.type != closeTokenType) {
		args ~= trange.parseAssignExpression();
		if (!trange.popOnMatch(TokenType.Comma)) {
			break;
		}
	}

	trange.match(closeTokenType);
	return args;
}

AstExpression[] parseArguments(ref TokenRange trange) {
	AstExpression[] args = [trange.parseAssignExpression()];
	while (trange.front.type == TokenType.Comma) {
		trange.popFront();

		args ~= trange.parseAssignExpression();
	}

	return args;
}

/**
 * Parse integer literals
 */
IntegerLiteral parseIntegerLiteral(ref TokenRange trange) {
	Location location = trange.front.location;

	// Consider computing the value in the lexer and make it a Name.
	// This would avoid the duplication with code here and probably
	// would be faster as well.
	auto strVal = trange.front.toString(trange.context);
	assert(strVal.length > 0);

	trange.match(TokenType.IntegerLiteral);

	bool isUnsigned, isLong;
	if (strVal.length > 1) {
		switch (strVal[$ - 1]) {
			case 'u', 'U':
				isUnsigned = true;

				auto penultimo = strVal[$ - 2];
				if (penultimo == 'l' || penultimo == 'L') {
					isLong = true;
					strVal = strVal[0 .. $ - 2];
				} else {
					strVal = strVal[0 .. $ - 1];
				}

				break;

			case 'l', 'L':
				isLong = true;

				auto penultimo = strVal[$ - 2];
				if (penultimo == 'u' || penultimo == 'U') {
					isUnsigned = true;
					strVal = strVal[0 .. $ - 2];
				} else {
					strVal = strVal[0 .. $ - 1];
				}

				break;

			default:
				break;
		}
	}

	import source.strtoint;
	ulong value = strToInt(strVal);

	import d.common.builtintype;
	auto type = isUnsigned
		? ((isLong || value > uint.max) ? BuiltinType.Ulong : BuiltinType.Uint)
		: ((isLong || value > int.max) ? BuiltinType.Long : BuiltinType.Int);

	return new IntegerLiteral(location, value, type);
}

/**
 * Parse character literals
 */
CharacterLiteral parseCharacterLiteral(ref TokenRange trange) {
	auto t = trange.match(TokenType.CharacterLiteral);

	import d.common.builtintype : BuiltinType;
	return new CharacterLiteral(t.location, t.decodedChar, BuiltinType.Char);
}

/**
 * Parse string literals
 */
StringLiteral parseStringLiteral(ref TokenRange trange) {
	Location location = trange.front.location;
	auto name = trange.front.name;

	trange.match(TokenType.StringLiteral);

	return new StringLiteral(location, name.toString(trange.context));
}

/**
 * Parse floating point literals
 */
FloatLiteral parseFloatLiteral(ref TokenRange trange) {
	const location = trange.front.location;
	auto litString = trange.front.toString(trange.context);

	trange.match(TokenType.FloatLiteral);
	import d.common.builtintype : BuiltinType;

	assert(litString.length > 1);
	// Look for a suffix
	switch (litString[$ - 1]) {
			// https://dlang.org/spec/lex.html#FloatSuffix
			import std.conv : to;
		case 'f':
		case 'F':
			const float f = litString[0 .. $ - 1].to!float;
			return new FloatLiteral(location, f, BuiltinType.Float);
		case 'L':
			import source.exception;
			throw new CompileException(
				location, "SDC does not support real literals yet");
		default:
			// Lexed correctly but no suffix, it's a double
			const double d = litString[0 .. $].to!double;
			return new FloatLiteral(location, d, BuiltinType.Double);
	}
}

@("Test FloatLiteral parsing")
unittest {
	import source.context;
	auto context = new Context();
	import source.parserutil;
	auto tokensFromString(string s) {
		import source.name;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		auto x = lex(base, context);
		x.match(TokenType.Begin);
		return x;
	}

	void floatRoundTrip(T)(const string floatString, const T floatValue)
			if (__traits(isFloating, T)) {
		import d.common.builtintype : BuiltinType;
		const BuiltinType expectedType =
			is(T == float) ? BuiltinType.Float : BuiltinType.Double;
		// Acceptable relativeError
		const T maxRelError = is(T == float) ? float.epsilon : double.epsilon;
		auto tr = tokensFromString(floatString);
		const fl = parseFloatLiteral(tr);

		import std.format : format;
		assert(
			fl,
			format("Got a %s from `%s`", typeid(fl).toString(), floatString)
		);

		assert(fl.type.builtin == expectedType);
		// Note that the value is store in the FloatLiteral as a double.
		if (fl.value !is floatValue) {
			import std.math : log10, abs;
			const relError = abs((fl.value - floatValue) / floatValue) * 100.0;
			assert(
				0,
				format(
					"%s yielded %f, missed by %e % whereas desired precision is %e",
					floatString, floatValue, relError, maxRelError)
			);
		}
	}

	// A few values, note that "-3.14f" is a UnaExp not a floating point literal
	floatRoundTrip("4.14f", 4.14f);
	floatRoundTrip("420.0", 420.0);
	floatRoundTrip("4200.0", 4200.0);
	floatRoundTrip("0.222225", 0.222225);
	floatRoundTrip("0x1p-52 ", 0x1p-52);
	// sdc can't lex this yet
	// floatRoundTrip("0x1.FFFFFFFFFFFFFp1023", 0x1.FFFFFFFFFFFFFp1023);
	floatRoundTrip("1.175494351e-38F", 1.175494351e-38F);
}
