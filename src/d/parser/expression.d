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
	return trange.parseAstBinaryExpression!(TokenType.Comma, AstBinaryOp.Comma,
	                                        parseAssignExpression)(lhs);
}

/**
 * Template used to parse basic AstBinaryExpressions.
 */
private AstExpression parseAstBinaryExpression(
	TokenType tokenType,
	AstBinaryOp op,
	alias parseNext,
)(ref TokenRange trange, AstExpression lhs) {
	lhs = parseNext(trange, lhs);

	while (trange.front.type == tokenType) {
		trange.popFront();

		auto rhs = trange.parsePrefixExpression();
		rhs = parseNext(trange, rhs);

		auto location = lhs.location.spanTo(trange.previous);
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

	static auto processToken(ref TokenRange trange, AstExpression lhs,
	                         AstBinaryOp op) {
		trange.popFront();

		auto rhs = trange.parsePrefixExpression();
		rhs = trange.parseAssignExpression(rhs);

		auto location = lhs.location.spanTo(trange.previous);
		return new AstBinaryExpression(location, op, lhs, rhs);
	}

	switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
		case Equal:
			return processToken(trange, lhs, Assign);

		case PlusEqual:
			return processToken(trange, lhs, AddAssign);

		case MinusEqual:
			return processToken(trange, lhs, SubAssign);

		case StarEqual:
			return processToken(trange, lhs, MulAssign);

		case SlashEqual:
			return processToken(trange, lhs, DivAssign);

		case PercentEqual:
			return processToken(trange, lhs, RemAssign);

		case AmpersandEqual:
			return processToken(trange, lhs, AndAssign);

		case PipeEqual:
			return processToken(trange, lhs, OrAssign);

		case CaretEqual:
			return processToken(trange, lhs, XorAssign);

		case TildeEqual:
			return processToken(trange, lhs, ConcatAssign);

		case LessLessEqual:
			return processToken(trange, lhs, LeftShiftAssign);

		case MoreMoreEqual:
			return processToken(trange, lhs, SignedRightShiftAssign);

		case MoreMoreMoreEqual:
			return processToken(trange, lhs, UnsignedRightShiftAssign);

		case CaretCaretEqual:
			return processToken(trange, lhs, PowAssign);

		default:
			// No assignement.
			return lhs;
	}
}

/**
 * Parse ?:
 */
AstExpression parseTernaryExpression(ref TokenRange trange,
                                     AstExpression condition) {
	condition = trange.parseLogicalOrExpression(condition);

	if (trange.front.type == TokenType.QuestionMark) {
		trange.popFront();
		auto ifTrue = trange.parseExpression();

		trange.match(TokenType.Colon);
		auto ifFalse = trange.parsePrefixExpression();
		ifFalse = trange.parseTernaryExpression(ifFalse);

		auto location = condition.location.spanTo(trange.previous);
		return new AstTernaryExpression(location, condition, ifTrue, ifFalse);
	}

	return condition;
}

/**
 * Parse ||
 */
auto parseLogicalOrExpression(ref TokenRange trange, AstExpression lhs) {
	return trange
		.parseAstBinaryExpression!(TokenType.PipePipe, AstBinaryOp.LogicalOr,
		                           parseLogicalAndExpression)(lhs);
}

/**
 * Parse &&
 */
auto parseLogicalAndExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(
		TokenType.AmpersandAmpersand, AstBinaryOp.LogicalAnd,
		parseBitwiseOrExpression)(lhs);
}

/**
 * Parse |
 */
auto parseBitwiseOrExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(TokenType.Pipe, AstBinaryOp.Or,
	                                        parseBitwiseXorExpression)(lhs);
}

/**
 * Parse ^
 */
auto parseBitwiseXorExpression(ref TokenRange trange, AstExpression lhs) {
	return trange.parseAstBinaryExpression!(TokenType.Caret, AstBinaryOp.Xor,
	                                        parseBitwiseAndExpression)(lhs);
}

/**
 * Parse &
 */
auto parseBitwiseAndExpression(ref TokenRange trange, AstExpression lhs) {
	return trange
		.parseAstBinaryExpression!(TokenType.Ampersand, AstBinaryOp.And,
		                           parseComparisonExpression)(lhs);
}

/**
 * Parse ==, != and comparaisons
 */
AstExpression parseComparisonExpression(ref TokenRange trange,
                                        AstExpression lhs) {
	lhs = trange.parseShiftExpression(lhs);

	static auto processToken(ref TokenRange trange, AstExpression lhs,
	                         AstBinaryOp op) {
		trange.popFront();

		auto rhs = trange.parsePrefixExpression();
		rhs = trange.parseShiftExpression(rhs);

		auto location = lhs.location.spanTo(trange.previous);
		return new AstBinaryExpression(location, op, lhs, rhs);
	}

	switch (trange.front.type) with (TokenType) {
		case EqualEqual:
			return processToken(trange, lhs, AstBinaryOp.Equal);

		case BangEqual:
			return processToken(trange, lhs, AstBinaryOp.NotEqual);

		case GreaterThan:
			return processToken(trange, lhs, AstBinaryOp.GreaterThan);

		case GreaterEqual:
			return processToken(trange, lhs, AstBinaryOp.GreaterEqual);

		case SmallerThan:
			return processToken(trange, lhs, AstBinaryOp.SmallerThan);

		case SmallerEqual:
			return processToken(trange, lhs, AstBinaryOp.SmallerEqual);

		case BangLessMoreEqual:
			return processToken(trange, lhs, AstBinaryOp.Unordered);

		case BangLessMore:
			return processToken(trange, lhs, AstBinaryOp.UnorderedEqual);

		case LessMore:
			return processToken(trange, lhs, AstBinaryOp.LessGreater);

		case LessMoreEqual:
			return processToken(trange, lhs, AstBinaryOp.LessEqualGreater);

		case BangMore:
			return processToken(trange, lhs, AstBinaryOp.UnorderedLessEqual);

		case BangMoreEqual:
			return processToken(trange, lhs, AstBinaryOp.UnorderedLess);

		case BangLess:
			return processToken(trange, lhs, AstBinaryOp.UnorderedGreaterEqual);

		case BangLessEqual:
			return processToken(trange, lhs, AstBinaryOp.UnorderedGreater);

		case Is:
			return processToken(trange, lhs, AstBinaryOp.Identical);

		case In:
			return processToken(trange, lhs, AstBinaryOp.In);

		case Bang:
			trange.popFront();
			switch (trange.front.type) {
				case Is:
					return processToken(trange, lhs, AstBinaryOp.NotIdentical);

				case In:
					return processToken(trange, lhs, AstBinaryOp.NotIn);

				default:
					throw unexpectedTokenError(trange, "is or in");
			}

		default:
			// We have no comparaison, so we just return.
			return lhs;
	}
}

/**
 * Parse <<, >> and >>>
 */
AstExpression parseShiftExpression(ref TokenRange trange, AstExpression lhs) {
	lhs = trange.parseAddExpression(lhs);

	while (true) {
		static auto processToken(ref TokenRange trange, AstExpression lhs,
		                         AstBinaryOp op) {
			trange.popFront();

			auto rhs = trange.parsePrefixExpression();
			rhs = trange.parseAddExpression(rhs);

			auto location = lhs.location.spanTo(trange.previous);
			return new AstBinaryExpression(location, op, lhs, rhs);
		}

		switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
			case LessLess:
				lhs = processToken(trange, lhs, LeftShift);
				break;

			case MoreMore:
				lhs = processToken(trange, lhs, SignedRightShift);
				break;

			case MoreMoreMore:
				lhs = processToken(trange, lhs, UnsignedRightShift);
				break;

			default:
				return lhs;
		}
	}
}

/**
 * Parse +, - and ~
 */
AstExpression parseAddExpression(ref TokenRange trange, AstExpression lhs) {
	lhs = trange.parseMulExpression(lhs);

	while (true) {
		static auto processToken(ref TokenRange trange, AstExpression lhs,
		                         AstBinaryOp op) {
			trange.popFront();

			auto rhs = trange.parsePrefixExpression();
			rhs = trange.parseMulExpression(rhs);

			auto location = lhs.location.spanTo(trange.previous);
			return new AstBinaryExpression(location, op, lhs, rhs);
		}

		switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
			case Plus:
				lhs = processToken(trange, lhs, Add);
				break;

			case Minus:
				lhs = processToken(trange, lhs, Sub);
				break;

			case Tilde:
				lhs = processToken(trange, lhs, Concat);
				break;

			default:
				return lhs;
		}
	}
}

/**
 * Parse *, / and %
 */
AstExpression parseMulExpression(ref TokenRange trange, AstExpression lhs) {
	while (true) {
		static auto processToken(ref TokenRange trange, AstExpression lhs,
		                         AstBinaryOp op) {
			trange.popFront();
			auto rhs = trange.parsePrefixExpression();

			auto location = lhs.location.spanTo(trange.previous);
			return new AstBinaryExpression(location, op, lhs, rhs);
		}

		switch (trange.front.type) with (AstBinaryOp) with (TokenType) {
			case Star:
				lhs = processToken(trange, lhs, Mul);
				break;

			case Slash:
				lhs = processToken(trange, lhs, Div);
				break;

			case Percent:
				lhs = processToken(trange, lhs, Rem);
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

	static auto processToken(ref TokenRange trange, UnaryOp op) {
		auto location = trange.front.location;
		trange.popFront();

		// Drop mode on purpose.
		auto e = trange.parsePrefixExpression();
		return new AstUnaryExpression(location.spanTo(trange.previous), op, e);
	}

	switch (trange.front.type) with (TokenType) {
		case Ampersand:
			result = processToken(trange, UnaryOp.AddressOf);
			break;

		case PlusPlus:
			result = processToken(trange, UnaryOp.PreInc);
			break;

		case MinusMinus:
			result = processToken(trange, UnaryOp.PreDec);
			break;

		case Star:
			result = processToken(trange, UnaryOp.Dereference);
			break;

		case Plus:
			result = processToken(trange, UnaryOp.Plus);
			break;

		case Minus:
			result = processToken(trange, UnaryOp.Minus);
			break;

		case Bang:
			result = processToken(trange, UnaryOp.Not);
			break;

		case Tilde:
			result = processToken(trange, UnaryOp.Complement);
			break;

		// TODO: parse qualifier casts.
		case Cast:
			auto location = trange.front.location;
			trange.popFront();
			trange.match(OpenParen);

			switch (trange.front.type) {
				case CloseParen:
					assert(0, "cast() isn't supported.");

				default:
					auto type = trange.parseType();
					trange.match(CloseParen);

					result = trange.parsePrefixExpression();
					result =
						new AstCastExpression(location.spanTo(trange.previous),
						                      type, result);
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
	auto t = trange.front;
	auto location = t.location;

	switch (t.type) with (TokenType) {
		// Identified expressions
		case Identifier:
			return trange.parseIdentifierExpression(trange.parseIdentifier());

		case New:
			trange.popFront();
			auto type = trange.parseType();
			auto args = trange.parseArguments!OpenParen();
			return new AstNewExpression(location.spanTo(trange.previous), type,
			                            args);

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

			trange.match(CloseBracket);
			return
				new AstArrayLiteral(location.spanTo(trange.previous), values);

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
				trange.match(CloseParen);
				location = location.spanTo(trange.previous);

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
					return new DelegateLiteral(location.spanTo(trange.previous),
					                           params, isVariadic, block);

				case FatArrow:
					import d.parser.declaration;
					bool isVariadic;
					auto params = trange.parseParameters(isVariadic);
					assert(!isVariadic, "Variadic lambda not supported");

					trange.match(FatArrow);

					auto value = trange.parseExpression();
					return new Lambda(location.spanTo(trange.previous), params,
					                  value);

				default:
					trange.popFront();
					auto expression = trange.parseExpression();

					trange.match(CloseParen);
					return new ParenExpression(location.spanTo(trange.previous),
					                           expression);
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
					return new TypeCallExpression(
						location.spanTo(trange.previous), type, args);

				default:
					break;
			}

			throw unexpectedTokenError(trange, "an expression");
	}
}

/**
 * Parse postfix ++, --, (...), [...], .identifier
 */
AstExpression parsePostfixExpression(ParseMode mode)(ref TokenRange trange,
                                                     AstExpression e) {
	auto location = e.location;

	while (true) {
		switch (trange.front.type) with (TokenType) {
			case PlusPlus:
				trange.popFront();
				e = new AstUnaryExpression(location.spanTo(trange.previous),
				                           UnaryOp.PostInc, e);
				break;

			case MinusMinus:
				trange.popFront();
				e = new AstUnaryExpression(location.spanTo(trange.previous),
				                           UnaryOp.PostDec, e);
				break;

			case OpenParen:
				auto args = trange.parseArguments!OpenParen();
				e = new AstCallExpression(location.spanTo(trange.previous), e,
				                          args);
				break;

			// TODO: Indices, Slices.
			case OpenBracket: {
				trange.popFront();

				if (trange.front.type == CloseBracket) {
					// We have a slicing operation here.
					assert(0, "Slice expressions can not be parsed yet");
				}

				auto args = trange.parseArguments();
				auto t = trange.front;
				switch (t.type) {
					case CloseBracket:
						trange.popFront();
						e = new AstIndexExpression(
							location.spanTo(trange.previous), e, args);
						break;

					case DotDot:
						trange.popFront();
						auto second = trange.parseArguments();

						trange.match(CloseBracket);
						e = new AstSliceExpression(
							location.spanTo(trange.previous), e, args, second);
						break;

					default:
						throw unexpectedTokenError(trange, "`]` or `..`");
				}
			}

				// FIXME: Get sdfmt to format the previous block
				// properly even without this break.
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
	while (trange.front.type == TokenType.CaretCaret) {
		trange.popFront();
		AstExpression power = trange.parsePrefixExpression();
		auto location = expr.location.spanTo(trange.previous);
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

	trange.match(TokenType.CloseParen);
	return new IsExpression(location.spanTo(trange.previous), type);
}

/**
 * Parse identifier expression
 */
AstExpression parseIdentifierExpression(ref TokenRange trange, Identifier i) {
	if (trange.front.type != TokenType.OpenParen) {
		return new IdentifierExpression(i);
	}

	auto args = trange.parseArguments!(TokenType.OpenParen)();
	auto location = i.location.spanTo(trange.previous);
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
	auto t = trange.match(TokenType.IntegerLiteral);

	// Consider computing the value in the lexer and make it a Name.
	// This would avoid the duplication with code here and probably
	// would be faster as well.
	auto strVal = t.toString(trange.context);
	assert(strVal.length > 0);

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

	ulong value = t.packedInt.toInt(trange.context);

	import d.common.builtintype;
	auto type = isUnsigned
		? ((isLong || value > uint.max) ? BuiltinType.Ulong : BuiltinType.Uint)
		: ((isLong || value > int.max) ? BuiltinType.Long : BuiltinType.Int);

	return new IntegerLiteral(t.location, value, type);
}

/**
 * Parse character literals
 */
CharacterLiteral parseCharacterLiteral(ref TokenRange trange) {
	auto t = trange.match(TokenType.CharacterLiteral);

	auto dc = t.decodedChar;
	return dc.isChar
		? new CharacterLiteral(t.location, dc.asChar)
		: new CharacterLiteral(t.location, dc.asDchar);
}

/**
 * Parse string literals
 */
StringLiteral parseStringLiteral(ref TokenRange trange) {
	auto t = trange.match(TokenType.StringLiteral);
	return
		new StringLiteral(t.location, t.decodedString.toString(trange.context));
}

/**
 * Parse floating point literals
 */
FloatLiteral parseFloatLiteral(ref TokenRange trange) {
	auto t = trange.match(TokenType.FloatLiteral);

	auto litString = t.toString(trange.context);
	assert(litString.length > 1);

	// https://dlang.org/spec/lex.html#FloatSuffix
	switch (litString[$ - 1]) {
		case 'f', 'F':
			import d.common.builtintype;
			return new FloatLiteral(
				t.location, t.packedFloat.to!float(trange.context),
				BuiltinType.Float);

		case 'L':
			import source.exception;
			throw new CompileException(
				t.location, "SDC does not support real literals yet");

		default:
			// Lexed correctly but no suffix, it's a double.
			import d.common.builtintype;
			return new FloatLiteral(
				t.location, t.packedFloat.to!double(trange.context),
				BuiltinType.Double);
	}
}

@("Test FloatLiteral parsing")
unittest {
	import source.context;
	auto context = new Context();

	auto makeTestLexer(string s) {
		auto base = context.registerMixin(Location.init, s ~ '\0');
		auto lexer = lex(base, context);

		lexer.match(TokenType.Begin);
		return lexer;
	}

	void floatRoundTrip(T)(const string floatString, const T floatValue) {
		import d.common.builtintype;
		enum ExpectedType =
			is(T == float) ? BuiltinType.Float : BuiltinType.Double;

		auto lexer = makeTestLexer(floatString);
		const fl = lexer.parseFloatLiteral();
		assert(fl.type.builtin == ExpectedType);

		// Note that the value is stored in the FloatLiteral as a double.
		assert(fl.value is floatValue);
	}

	// A few values, note that "-3.14f" is an unary expression
	// not a floating point literal.
	floatRoundTrip("4.14f", 4.14f);
	floatRoundTrip("420.0", 420.0);
	floatRoundTrip("4200.0", 4200.0);
	floatRoundTrip("0.222225", 0.222225);
	floatRoundTrip("0x1p-52 ", 0x1p-52);
	floatRoundTrip("0x1.FFFFFFFFFFFFFp1023", 0x1.FFFFFFFFFFFFFp1023);
	floatRoundTrip("1.175494351e-38F", 1.175494351e-38F);
}
