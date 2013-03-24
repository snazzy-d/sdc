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
typeof(handler(null)) parseAmbiguous(alias handler, R)(ref R trange) if(isTokenRange!R) {
	switch(trange.front.type) with(TokenType) {
		case Identifier :
			auto i = trange.parseIdentifier();
			return trange.parseAmbiguousSuffix!handler(i);
		
		case Dot :
			auto i = trange.parseDotIdentifier();
			return trange.parseAmbiguousSuffix!handler(i);
		
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
		case Char :
		case Wchar :
		case Dchar :
		case Float :
		case Double :
		case Real :
		case Void :
			auto t = trange.parseType!(ParseMode.Reluctant)();
			return trange.parseAmbiguousSuffix!handler(t);
		
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
		case OpenParen :
		
		// Prefixes.
		case Ampersand :
		case DoublePlus :
		case DoubleMinus :
		case Star :
		case Plus :
		case Minus :
		case Bang :
		case Tilde :
		case Cast :
			auto e = trange.parseExpression!(ParseMode.Reluctant)();
			return trange.parseAmbiguousSuffix!handler(e);
		
		default :
			trange.match(TokenType.Begin);
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
				static if(is(typeof(parsed) : Type)) {
					return trange.parseTypedDeclaration(location, parsed);
				} else static if(is(typeof(parsed) : Expression)) {
					return parsed;
				} else {
					if(trange.front.type == TokenType.Identifier) {
						return trange.parseTypedDeclaration(location, new IdentifierType(parsed));
					} else {
						return new IdentifierExpression(parsed);
					}
				}
			})();
			
			// XXX: workaround lolbug (handler can't be passed down to subfunction).
			if(auto d = cast(Declaration) parsed) {
				return handler(d);
			} else if(auto e = cast(Expression) parsed) {
				return handler(e);
			}
			
			assert(0);
	}
}

private:
// XXX: Workaround template recurence instanciation bug.
enum Tag {
	Identifier,
	Expression,
	Type,
}

struct Ambiguous {
	Tag tag;
	
	union {
		Identifier i;
		Expression e;
		Type t;
	}
	
	@disable this();
	
	// For type inference.
	this(typeof(null));
	
	this(Ambiguous a) {
		this = a;
	}
	
	this(Identifier id) {
		tag = Tag.Expression;
		i = id;
	}
	
	this(Expression exp) {
		tag = Tag.Expression;
		e = exp;
	}
	
	this(Type type) {
		tag = Tag.Type;
		t = type;
	}
}

Ambiguous ambiguousHandler(T)(T t) {
	static if(is(T == typeof(null))) {
		assert(0);
	} else {
		return Ambiguous(t);
	}
}

auto apply(alias handler)(Ambiguous a) {
	final switch(a.tag) {
		case Tag.Identifier :
			return handler(a.i);
		
		case Tag.Expression :
			return handler(a.e);
		
		case Tag.Type :
			return handler(a.t);
	}
}

private typeof(handler(null)) parseAmbiguousSuffix(alias handler, R)(ref R trange, Identifier i) {
	switch(trange.front.type) with(TokenType) {
		case OpenBracket :
			trange.popFront();
			
			auto parsed = trange.parseAmbiguous!ambiguousHandler().apply!(delegate Object(parsed) {
				auto location = i.location;
				location.spanTo(trange.front.location);
				
				static if(is(typeof(parsed) : Type)) {
					return new AssociativeArrayType(location, new IdentifierType(i), parsed);
				} else static if(is(typeof(parsed) : Expression)) {
					return new IdentifierBracketExpression(location, i, parsed);
				} else {
					return new IdentifierBracketIdentifier(location, i, parsed);
				}
			})();
			
			trange.match(CloseBracket);
			
			// XXX: workaround lolbug (handler can't be passed down to subfunction).
			if(auto id = cast(d.ast.identifier.Identifier) parsed) {
				return trange.parseAmbiguousSuffix!ambiguousHandler(id).apply!handler();
			} else if(auto t = cast(Type) parsed) {
				return trange.parseAmbiguousSuffix!handler(t);
			}
			
			assert(0);	
		
		case Function :
		case Delegate :
			auto t = trange.parseTypeSuffix!(ParseMode.Reluctant)(new IdentifierType(i));
			return trange.parseAmbiguousSuffix!handler(t);
		
		case DoublePlus :
		case DoubleMinus :
		case OpenParen :
			auto e = trange.parsePostfixExpression!(ParseMode.Reluctant)(new IdentifierExpression(i));
			return trange.parseAmbiguousSuffix!handler(e);
		
		// FIXME: Add binary operators.
		case Star :
			assert(0, "Can be a pointer or an expression, or maybe even a declaration. That is bad !");
		
		case Assign :
		case PlusAssign :
		case MinusAssign :
		case StarAssign :
		case SlashAssign :
		case PercentAssign :
		case AmpersandAssign :
		case PipeAssign :
		case CaretAssign :
		case TildeAssign :
		case DoubleLessAssign :
		case DoubleMoreAssign :
		case TripleMoreAssign :
		case DoubleCaretAssign :
			auto e = trange.parseAssignExpression(new IdentifierExpression(i));
			return trange.parseAmbiguousSuffix!handler(e);
		
		default :
			return handler(i);
	}
}

private typeof(handler(null)) parseAmbiguousSuffix(alias handler, R)(ref R trange, Type t) {
	switch(trange.front.type) with(TokenType) {
		case OpenParen :
			assert(0, "Constructor not implemented");
		
		case Dot :
			trange.popFront();
			
			auto i = trange.parseQualifiedIdentifier(t.location, t);
			return trange.parseAmbiguousSuffix!ambiguousHandler(i).apply!handler();
		
		default :
			return handler(t);
	}
}

private typeof(handler(null)) parseAmbiguousSuffix(alias handler, R)(ref R trange, Expression e) {
	switch(trange.front.type) with(TokenType) {
		case Dot :
			trange.popFront();
			
			auto i = trange.parseQualifiedIdentifier(e.location, e);
			return trange.parseAmbiguousSuffix!ambiguousHandler(i).apply!handler();
		
		default :
			return handler(e);
	}
}

