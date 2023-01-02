module d.parser.ambiguous;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;
import d.parser.identifier;
import source.parserutil;

/**
 * Branch to the right code depending if we have a type,
 * an expression or an identifier.
 */
typeof(handler(AstExpression.init)) parseAmbiguous(
	alias handler,
	AmbiguousParseMode M = AmbiguousParseMode.Regular,
)(ref TokenRange trange) {
	switch (trange.front.type) with (TokenType) {
		case Identifier:
			auto i = trange.parseIdentifier();
			return trange.parseAmbiguousSuffix!(handler, M)(i);

		case Dot:
			auto i = trange.parseDotIdentifier();
			return trange.parseAmbiguousSuffix!(handler, M)(i);

		// Types
		case Typeof:
		case Bool:
		case Byte, Ubyte:
		case Short, Ushort:
		case Int, Uint:
		case Long, Ulong:
		case Cent, Ucent:
		case Char, Wchar, Dchar:
		case Float, Double, Real:
		case Void:

		// Type qualifiers
		case Const, Immutable, Inout, Shared:
			auto location = trange.front.location;
			auto t = trange.parseType!(ParseMode.Reluctant)();
			return trange.parseAmbiguousSuffix!(handler, M)(location, t);

		case New:
		case This:
		case Super:
		case True:
		case False:
		case Null:
		case IntegerLiteral:
		case StringLiteral:
		case CharacterLiteral:
		case OpenBracket:
		case OpenBrace:
		case Function:
		case Delegate:
		case __File__:
		case __Line__:
		case Dollar:
		case Typeid:
		case Is:

		// XXX: Should assert really be an expression ?
		case Assert:

		// Prefixes.
		case Ampersand:
		case PlusPlus:
		case MinusMinus:
		case Star:
		case Plus:
		case Minus:
		case Bang:
		case Tilde:
		case Cast:
			auto e = trange.parseExpression!(ParseMode.Reluctant)();
			return trange.parseAmbiguousSuffix!(handler, M)(e);

		case OpenParen:
			auto matchingParen = trange.getLookahead();
			matchingParen.popMatchingDelimiter!OpenParen();

			switch (matchingParen.front.type) {
				case OpenBrace, FatArrow:
					// Delegates.
					assert(0, "Ambiguous delegates not implemented");

				default:
					auto location = trange.front.location;
					trange.popFront();

					// Use ambiguousHandler to avoid infinite recursion
					return trange.parseAmbiguous!ambiguousHandler().apply!((
						parsed
					) {
						trange.match(CloseParen);
						location = location.spanTo(trange.previous);

						alias T = typeof(parsed);
						static if (is(T : AstType)) {
							return trange
								.parseAmbiguousSuffix!(handler, M)(location,
								                                   parsed);
						} else static if (is(T : AstExpression)) {
							auto e = new ParenExpression(location, parsed);
							return trange.parseAmbiguousSuffix!(handler, M)(e);
						} else {
							// XXX: Consider adding ParenIdentifier for AST fidelity.
							return trange
								.parseAmbiguousSuffix!(handler, M)(parsed);
						}
					})();
			}

		default:
			throw unexpectedTokenError(trange, "a type or an expression");
	}
}

struct IdentifierStarName {
	import source.name;
	Name name;

	Identifier identifier;
	AstExpression value;
}

auto parseAmbiguousStatement(ref TokenRange trange) {
	switch (trange.front.type) with (TokenType) {
		case Interface, Class, Struct, Union, Enum:
		case Import, Template, Extern, Alias:
		case Auto, Static, Const, Immutable, Inout, Shared:
			auto d = trange.parseDeclaration();
			return trange.finalizeStatement(d.location, d);

		default:
			auto location = trange.front.location;
			return trange.parseAmbiguous!(
				parsed => trange.finalizeStatement(location, parsed),
				AmbiguousParseMode.Declaration,
			)();
	}
}

auto parseStatementSuffix(ref TokenRange trange, AstExpression e) {
	return trange.parseAmbiguousSuffix!(
		parsed => trange.finalizeStatement(e.location, parsed),
		AmbiguousParseMode.Declaration,
	)(e);
}

private:

Declaration finalizeDeclaration(T)(ref TokenRange trange, Location location,
                                   T parsed) {
	static if (is(T : AstType)) {
		alias t = parsed;
	} else {
		auto t = AstType.get(parsed);
	}

	return trange.parseTypedDeclaration(location, defaultStorageClass, t);
}

Statement finalizeStatement(T)(ref TokenRange trange, Location location,
                               T parsed) {
	static if (is(T : AstType)) {
		return trange
			.finalizeStatement(location,
			                   trange.finalizeDeclaration(location, parsed));
	} else static if (is(T : Declaration)) {
		return new DeclarationStatement(parsed);
	} else static if (is(T : AstExpression)) {
		trange.match(TokenType.Semicolon);
		return new ExpressionStatement(parsed);
	} else static if (is(T : IdentifierStarName)) {
		trange.match(TokenType.Semicolon);
		return new IdentifierStarNameStatement(
			location.spanTo(trange.previous), parsed.identifier, parsed.name,
			parsed.value);
	} else {
		// Identifier follow by another identifier is a declaration.
		if (trange.front.type == TokenType.Identifier) {
			return trange.finalizeStatement(
				location, trange.finalizeDeclaration(location, parsed));
		} else {
			return trange
				.finalizeStatement(location, new IdentifierExpression(parsed));
		}
	}
}

/**
 * Indicate if we are looking for something that may be a declaration.
 * This is relevent for statements, which can be expression or declaration,
 * but not true in the general case. This is relevent for special cases such
 * as:
 *   Identifier * Identifier = Expression.
 *
 * Such statement can either be a declaration or an expression if the mode
 * is declaration, but will be considered an expression if it is regular.
 */
enum AmbiguousParseMode {
	Regular,
	Declaration,
}

// XXX: Workaround template recurence instanciation bug.
alias Ambiguous = AstType.UnionType!(Identifier, AstExpression);

auto apply(alias handler)(Ambiguous a) {
	alias Tag = typeof(a.tag);
	final switch (a.tag) with (Tag) {
		case Identifier:
			return handler(a.get!Identifier);

		case AstExpression:
			return handler(a.get!AstExpression);

		case AstType:
			return handler(a.get!AstType);
	}
}

Ambiguous ambiguousHandler(T)(T t) {
	static if (is(T == typeof(null))) {
		assert(0);
	} else {
		return Ambiguous(t);
	}
}

bool indicateExpression(TokenType t) {
	switch (t) with (TokenType) {
		case PlusPlus:
		case MinusMinus:
		case Equal:
		case PlusEqual:
		case MinusEqual:
		case StarEqual:
		case SlashEqual:
		case PercentEqual:
		case AmpersandEqual:
		case PipeEqual:
		case CaretEqual:
		case TildeEqual:
		case LessLessEqual:
		case MoreMoreEqual:
		case MoreMoreMoreEqual:
		case CaretCaretEqual:
		case QuestionMark:
		case PipePipe:
		case AmpersandAmpersand:
		case Pipe:
		case Caret:
		case Ampersand:
		case EqualEqual:
		case BangEqual:
		case GreaterThan:
		case GreaterEqual:
		case SmallerThan:
		case SmallerEqual:
		case BangLessMoreEqual:
		case BangLessMore:
		case LessMore:
		case LessMoreEqual:
		case BangMore:
		case BangMoreEqual:
		case BangLess:
		case BangLessEqual:
		case Is:
		case In:
		case Bang:
		case LessLess:
		case MoreMore:
		case MoreMoreMore:
		case Plus:
		case Minus:
		case Tilde:
		case Slash:
		case Percent:
		case OpenParen:
			return true;

		default:
			return false;
	}
}

typeof(handler(AstExpression.init)) parseAmbiguousSuffix(
	alias handler,
	AmbiguousParseMode M = AmbiguousParseMode.Type,
)(ref TokenRange trange, Identifier i) {
	auto tt = trange.front.type;
	if (tt.indicateExpression()) {
		auto e = trange.parseIdentifierExpression(i);
		return trange.parseAmbiguousSuffix!handler(e);
	}

	switch (tt) with (TokenType) {
		case OpenBracket:
			trange.popFront();

			// This is a slice type
			if (trange.front.type == CloseBracket) {
				trange.popFront();
				return trange
					.parseAmbiguousSuffix!handler(i.location,
					                              AstType.get(i).getSlice());
			}

			return trange.parseAmbiguous!ambiguousHandler().apply!((parsed) {
				auto location = i.location;
				trange.match(CloseBracket);
				location = location.spanTo(trange.previous);

				alias T = typeof(parsed);
				static if (is(T : AstType)) {
					auto t = AstType.get(i).getMap(parsed);
					return trange.parseAmbiguousSuffix!handler(i.location, t);
				} else {
					static if (is(T : AstExpression)) {
						auto id = new IdentifierBracketExpression(location, i,
						                                          parsed);
					} else {
						auto id = new IdentifierBracketIdentifier(location, i,
						                                          parsed);
					}

					return trange.parseAmbiguousSuffix!(handler, M)(id);
				}
			})();

		case Star:
			auto lookahead = trange.getLookahead();
			lookahead.popFront();

			switch (lookahead.front.type) {
				Type:
					return trange.parseAmbiguousSuffix!handler(i.location,
					                                           AstType.get(i));

					Expression: {
						auto lhs = new IdentifierExpression(i);
						auto e = trange.parseMulExpression(lhs);
						return trange.parseAmbiguousSuffix!handler(e);
					}

				case Star:
					// Identifier** is a pointer to a pointer.
					goto Type;

				case OpenBracket:
					// XXX: Array literal or array/slice/map of pointer ?
					assert(0, "Not supported");

				case Function, Delegate:
					lookahead.popFront();

					if (lookahead.front.type == OpenParen) {
						// Function type returning a pointer.
						goto Type;
					}

					// IdentifierExpression * function Type(...)
					goto Expression;

				case New:
				case This, Super:
				case True, False:
				case Null:
				case IntegerLiteral:
				case StringLiteral:
				case CharacterLiteral:
				case OpenBrace:
				case __File__, __Line__:
				case Dollar:
				case Typeid:
				case Is:
				case Assert:
					// These indicate an expression.
					goto Expression;

				case Identifier:
					/**
					 * Deal with:
					 *     Identifier * Name = Initializer
					 *     Identifier * identifier(
					 * As both can be expression or declaration depending
					 * on identifier resolution.
					 */
					static if (M == AmbiguousParseMode.Declaration) {
						auto name = lookahead.front.name;
						auto rloc = lookahead.front.location;

						lookahead.popFront();
						auto rtt = lookahead.front.type;
						switch (rtt) {
							case Equal:
								/**
								 * Identifier * Name = Initializer can be
								 * an expression or a declaration. Create
								 * a special node and let identifier resolution
								 * deal with it.
								 */
								trange.moveTo(lookahead);
								trange.popFront();
								auto v = trange.parseInitializer();
								return handler(IdentifierStarName(name, i, v));

							case OpenParen:
								/**
								 * We are faced with Identifier * Identifier(
								 * It is either the start of an expression or
								 * the start of the declaration of a function
								 * that returns a pointer.
								 * In any case, we'll assume the later.
								 */
								trange.popFront();
								return handler(trange.parseTypedDeclaration(
									i.location, defaultStorageClass,
									AstType.get(i).getPointer()));

							default:
								// FIXME: This is most likely broken.
								// Cases like *, . and ! are not handled.
								if (!rtt.indicateExpression()) {
									trange.moveTo(lookahead);
									return handler(
										IdentifierStarName(name, i, null));
								}
						}
					}

					// Otherwize, it is an expression.
					goto Expression;

				case Semicolon:
					// This indicate an end of statement, so we have a type.
					goto Type;

				default:
					throw
						unexpectedTokenError(trange, "a type or an expression");
			}

		case Dot:
			trange.popFront();

			auto id = trange.parseQualifiedIdentifier(i.location, i);
			return trange.parseAmbiguousSuffix!(handler, M)(id);

		case Function, Delegate:
			return
				trange.parseAmbiguousSuffix!handler(i.location, AstType.get(i));

		default:
			return handler(i);
	}
}

typeof(handler(AstExpression.init)) parseAmbiguousSuffix(
	alias handler,
	AmbiguousParseMode M = AmbiguousParseMode.Regular,
)(ref TokenRange trange, Location location, AstType t) {
	t = trange.parseTypeSuffix!(ParseMode.Reluctant)(t);

	switch (trange.front.type) with (TokenType) {
		case OpenParen:
			assert(0, "Constructor not implemented");

		case Dot:
			trange.popFront();

			auto i = trange.parseQualifiedIdentifier(location, t);
			return trange.parseAmbiguousSuffix!(handler, M)(i);

		default:
			return handler(t);
	}
}

typeof(handler(AstExpression.init)) parseAmbiguousSuffix(
	alias handler,
	AmbiguousParseMode M = AmbiguousParseMode.Regular,
)(ref TokenRange trange, AstExpression e) {
	e = trange.parsePostfixExpression!(ParseMode.Reluctant)(e);

	while (true) {
		switch (trange.front.type) with (TokenType) {
			case Equal:
			case PlusEqual:
			case MinusEqual:
			case StarEqual:
			case SlashEqual:
			case PercentEqual:
			case AmpersandEqual:
			case PipeEqual:
			case CaretEqual:
			case TildeEqual:
			case LessLessEqual:
			case MoreMoreEqual:
			case MoreMoreMoreEqual:
			case CaretCaretEqual:
				e = trange.parseAssignExpression(e);
				continue;

			case QuestionMark:
				e = trange.parseTernaryExpression(e);
				continue;

			case PipePipe:
				e = trange.parseLogicalOrExpression(e);
				continue;

			case AmpersandAmpersand:
				e = trange.parseLogicalAndExpression(e);
				continue;

			case Pipe:
				e = trange.parseBitwiseOrExpression(e);
				continue;

			case Caret:
				e = trange.parseBitwiseXorExpression(e);
				continue;

			case Ampersand:
				e = trange.parseBitwiseAndExpression(e);
				continue;

			case EqualEqual:
			case BangEqual:
			case GreaterThan:
			case GreaterEqual:
			case SmallerThan:
			case SmallerEqual:
			case BangLessMoreEqual:
			case BangLessMore:
			case LessMore:
			case LessMoreEqual:
			case BangMore:
			case BangMoreEqual:
			case BangLess:
			case BangLessEqual:
			case Is:
			case In:
			case Bang:
				e = trange.parseComparisonExpression(e);
				continue;

			case LessLess, MoreMore, MoreMoreMore:
				e = trange.parseShiftExpression(e);
				continue;

			case Plus, Minus, Tilde:
				e = trange.parseAddExpression(e);
				continue;

			case Star, Slash, Percent:
				e = trange.parseMulExpression(e);
				continue;

			case Dot:
				trange.popFront();

				auto i = trange.parseQualifiedIdentifier(e.location, e);
				return trange.parseAmbiguousSuffix!(handler, M)(i);

			default:
				return handler(e);
		}
	}
}
