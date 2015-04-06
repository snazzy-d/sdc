module d.parser.ambiguous;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;
import d.parser.identifier;
import d.parser.util;

import std.range;

/**
 * Branch to the right code depending if we have a type, an expression or an identifier.
 */
typeof(handler(AstType.init)) parseAmbiguous(alias handler, R)(ref R trange) if(isTokenRange!R) {
	switch(trange.front.type) with(TokenType) {
		case Identifier :
			auto i = trange.parseIdentifier();
			return trange.parseAmbiguousSuffix!handler(i);
		
		case Dot :
			auto i = trange.parseDotIdentifier();
			return trange.parseAmbiguousSuffix!handler(i);
		
		// Types
		case Typeof :
		case Bool :
		case Byte :
		case Ubyte :
		case Short :
		case Ushort :
		case Int :
		case Uint :
		case Long :
		case Ulong :
		case Cent :
		case Ucent :
		case Char :
		case Wchar :
		case Dchar :
		case Float :
		case Double :
		case Real :
		case Void :
		
		// Type qualifiers
		case Const :
		case Immutable :
		case Inout :
		case Shared :
			auto location = trange.front.location;
			auto t = trange.parseType!(ParseMode.Reluctant)();
			return trange.parseAmbiguousSuffix!handler(location, t);
		
		case New :
		case This :
		case Super :
		case True :
		case False :
		case Null :
		case IntegerLiteral :
		case StringLiteral :
		case CharacterLiteral :
		case OpenBracket :
		case OpenBrace :
		case Function :
		case Delegate :
		case __File__ :
		case __Line__ :
		case Dollar :
		case Typeid :
		case Is :
		case Assert :
		
		// Prefixes.
		case Ampersand :
		case PlusPlus :
		case MinusMinus :
		case Star :
		case Plus :
		case Minus :
		case Bang :
		case Tilde :
		case Cast :
			auto e = trange.parseExpression!(ParseMode.Reluctant)();
			return trange.parseAmbiguousSuffix!handler(e);
		
		case OpenParen :
			auto matchingParen = trange.save;
			matchingParen.popMatchingDelimiter!OpenParen();
			
			switch(matchingParen.front.type) {
				case OpenBrace, EqualMore :
					// Delegates.
					assert(0, "Ambiguous delegates not implemented");
				
				default :
					auto location = trange.front.location;
					trange.popFront();
					
					// Use ambiguousHandler to avoid infinite recursion
					return trange.parseAmbiguous!ambiguousHandler().apply!((parsed) {
						location.spanTo(trange.front.location);
						trange.match(CloseParen);
						
						alias T = typeof(parsed);
						static if (is(T : AstType)) {
							return trange.parseAmbiguousSuffix!ambiguousHandler(location, parsed).apply!handler();
						} else static if (is(T : AstExpression)) {
							auto e = new ParenExpression(location, parsed);
							return trange.parseAmbiguousSuffix!ambiguousHandler(e).apply!handler();
						} else {
							// XXX: Consider adding ParenIdentifier for AST fidelity.
							return trange.parseAmbiguousSuffix!ambiguousHandler(parsed).apply!handler();
						}
					})();
			}
		
		default :
			trange.match(Begin);
			// TODO: handle.
			// Erreur, unexpected.
			assert(0);
	}
}

auto parseDeclarationOrExpression(alias handler, R)(ref R trange) if(isTokenRange!R) {
	switch(trange.front.type) with(TokenType) {
		case Import, Interface, Class, Struct, Union, Enum, Template, Alias, Extern :
			// XXX: lolbug !
			goto case Auto;
		
		case Auto, Static, Const, Immutable, Inout, Shared :
			return handler(trange.parseDeclaration());
		
		default :
			auto location = trange.front.location;
			auto parsed = trange.parseAmbiguous!(delegate Object(parsed) {
				alias T = typeof(parsed);
				static if (is(T : AstType)) {
					return trange.parseTypedDeclaration(location, defaultStorageClass, parsed);
				} else static if (is(T : AstExpression)) {
					return parsed;
				} else {
					// Identifier follow by another identifier is a declaration.
					if (trange.front.type == TokenType.Identifier) {
						return trange.parseTypedDeclaration(location, defaultStorageClass, AstType.get(parsed));
					} else {
						return new IdentifierExpression(parsed);
					}
				}
			})();
			
			// XXX: workaround lolbug (handler can't be passed down to subfunction).
			if (auto d = cast(Declaration) parsed) {
				return handler(d);
			} else if (auto e = cast(AstExpression) parsed) {
				return handler(e);
			}
			
			assert(0);
	}
}

private:

// XXX: Workaround template recurence instanciation bug.
alias Ambiguous = AstType.UnionType!(Identifier, AstExpression);

auto apply(alias handler)(Ambiguous a) {
	alias Tag = typeof(a.tag);
	final switch(a.tag) with(Tag) {
		case Identifier :
			return handler(a.get!Identifier);
		
		case AstExpression :
			return handler(a.get!AstExpression);
		
		case AstType :
			return handler(a.get!AstType);
	}
}

Ambiguous ambiguousHandler(T)(T t) {
	static if(is(T == typeof(null))) {
		assert(0);
	} else {
		return Ambiguous(t);
	}
}

bool indicateExpression(TokenType t) {
	switch(t) with(TokenType) {
		case PlusPlus :
		case MinusMinus :
		case Assign :
		case PlusEqual :
		case MinusEqual :
		case StarEqual :
		case SlashEqual :
		case PercentEqual :
		case AmpersandEqual :
		case PipeEqual :
		case CaretEqual :
		case TildeEqual :
		case LessLessEqual :
		case MoreMoreEqual :
		case MoreMoreMoreEqual :
		case CaretCaretEqual :
		case QuestionMark :
		case PipePipe :
		case AmpersandAmpersand :
		case Pipe :
		case Caret :
		case Ampersand :
		case EqualEqual :
		case BangEqual :
		case More:
		case MoreEqual:
		case Less :
		case LessEqual :
		case BangLessMoreEqual:
		case BangLessMore:
		case LessMore:
		case LessMoreEqual:
		case BangMore:
		case BangMoreEqual:
		case BangLess:
		case BangLessEqual:
		case Is :
		case In :
		case Bang :
		case LessLess :
		case MoreMore :
		case MoreMoreMore :
		case Plus :
		case Minus :
		case Tilde :
		case Slash :
		case Percent :
			return true;
		
		default:
			return false;
	}
}

typeof(handler(null)) parseAmbiguousSuffix(alias handler, R)(ref R trange, Identifier i) {
	auto tt = trange.front.type;
	if (tt.indicateExpression()) {
		return trange.parseAmbiguousSuffix!handler(new IdentifierExpression(i));
	}
	
	switch(tt) with(TokenType) {
		case OpenBracket :
			trange.popFront();
			
			// This is a slice type
			if(trange.front.type == CloseBracket) {
				trange.popFront();
				return trange.parseAmbiguousSuffix!handler(i.location, AstType.get(i).getSlice());
			}
			
			return trange.parseAmbiguous!ambiguousHandler().apply!((parsed) {
				auto location = i.location;
				location.spanTo(trange.front.location);
				trange.match(CloseBracket);
				
				alias T = typeof(parsed);
				static if (is(T : AstType)) {
					auto t = AstType.get(i).getMap(parsed);
					return trange.parseAmbiguousSuffix!handler(i.location, t);
				} else {
					static if (is(T : AstExpression)) {
						auto id = new IdentifierBracketExpression(location, i, parsed);
					} else {
						auto id = new IdentifierBracketIdentifier(location, i, parsed);
					}
					
					// Use ambiguousHandler to avoid infinite recursion
					return trange.parseAmbiguousSuffix!ambiguousHandler(id).apply!handler();
				}
			})();
		
		case Star :
			trange.popFront();
			
			switch (trange.front.type) {
				case OpenBracket :
				case Star :
				case Function :
				case Delegate :
					return trange.parseAmbiguousSuffix!handler(i.location, AstType.get(i).getPointer());
				
				default :
					assert(0, "Can be a pointer or an expression, or maybe even a declaration. That is bad !");
			}
		
		case Dot :
			trange.popFront();
			
			auto id = trange.parseQualifiedIdentifier(i.location, i);
			return trange.parseAmbiguousSuffix!ambiguousHandler(id).apply!handler();
		
		case Function :
		case Delegate :
			return trange.parseAmbiguousSuffix!handler(i.location, AstType.get(i));
		
		case OpenParen :
			auto e = trange.parseIdentifierExpression(i);
			return trange.parseAmbiguousSuffix!handler(e);
		
		default :
			return handler(i);
	}
}

typeof(handler(null)) parseAmbiguousSuffix(alias handler, R)(ref R trange, Location location, AstType t) {
	t = trange.parseTypeSuffix!(ParseMode.Reluctant)(t);
	
	switch(trange.front.type) with(TokenType) {
		case OpenParen :
			assert(0, "Constructor not implemented");
		
		case Dot :
			trange.popFront();
			
			auto i = trange.parseQualifiedIdentifier(location, t);
			return trange.parseAmbiguousSuffix!ambiguousHandler(i).apply!handler();
		
		default :
			return handler(t);
	}
}

typeof(handler(null)) parseAmbiguousSuffix(alias handler, R)(ref R trange, AstExpression e) {
	e = trange.parsePostfixExpression!(ParseMode.Reluctant)(e);
	
	while(true) {
		switch(trange.front.type) with(TokenType) {
			case Assign :
			case PlusEqual :
			case MinusEqual :
			case StarEqual :
			case SlashEqual :
			case PercentEqual :
			case AmpersandEqual :
			case PipeEqual :
			case CaretEqual :
			case TildeEqual :
			case LessLessEqual :
			case MoreMoreEqual :
			case MoreMoreMoreEqual :
			case CaretCaretEqual :
				e = trange.parseAssignExpression(e);
				continue;
			
			case QuestionMark :
				e = trange.parseTernaryExpression(e);
				continue;
			
			case PipePipe :
				e = trange.parseLogicalOrExpression(e);
				continue;
			
			case AmpersandAmpersand :
				e = trange.parseLogicalAndExpression(e);
				continue;
			
			case Pipe :
				e = trange.parseBitwiseOrExpression(e);
				continue;
			
			case Caret :
				e = trange.parseBitwiseXorExpression(e);
				continue;
			
			case Ampersand :
				e = trange.parseBitwiseAndExpression(e);
				continue;
			
			case EqualEqual :
			case BangEqual :
			case More:
			case MoreEqual:
			case Less :
			case LessEqual :
			case BangLessMoreEqual:
			case BangLessMore:
			case LessMore:
			case LessMoreEqual:
			case BangMore:
			case BangMoreEqual:
			case BangLess:
			case BangLessEqual:
			case Is :
			case In :
			case Bang :
				e = trange.parseComparaisonExpression(e);
				continue;
			
			case LessLess :
			case MoreMore :
			case MoreMoreMore :
				e = trange.parseShiftExpression(e);
				continue;
			
			case Plus :
			case Minus :
			case Tilde :
				e = trange.parseAddExpression(e);
				continue;
			
			case Star :
			case Slash :
			case Percent :
				e = trange.parseMulExpression(e);
				continue;
			
			case Dot :
				trange.popFront();
				
				auto i = trange.parseQualifiedIdentifier(e.location, e);
				return trange.parseAmbiguousSuffix!ambiguousHandler(i).apply!handler();
			
			default :
				return handler(e);
		}
	}
}

