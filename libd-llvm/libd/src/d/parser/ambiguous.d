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
auto parseAmbiguous(alias handler, R)(ref R trange) if(isTokenRange!R) {
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
	switch(trange.front.type) {
		case TokenType.Auto, TokenType.Import, TokenType.Interface, TokenType.Class, TokenType.Struct, TokenType.Union, TokenType.Enum, TokenType.Template, TokenType.Alias, TokenType.Extern :
			return handler(trange.parseDeclaration());
		
		default :
			/+
			// FIXME: don't parse twice :/
			auto lookahead = trange.save;
			
			auto parsed = lookahead.parseAmbiguous!(delegate Object(parsed) {
				alias typeof(parsed) caseType;
				
				static if(is(caseType : Expression)) {
					return trange.parseExpression();
				} else {
					if(lookahead.front.type == TokenType.Identifier) {
						return trange.parseDeclaration();
					} else {
						return trange.parseExpression();
					}
				}
			})();
			
			if(auto d = cast(Declaration) parsed) {
				return handler(d);
			} else if(auto e = cast(Expression) parsed) {
				return handler(e);
			}
			
			assert(0);
			+/
			
			// FIXME: lolbug workaround.
			auto save = trange.save;
			try {
				return handler(trange.parseDeclaration());
			} catch(Exception e) {
				trange = save.save;
				
				import std.stdio;
				writeln("declaration didn't worked, back on expression.");
				
				return handler(trange.parseExpression());
			}
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


private typeof(handler(null)) parseAmbiguousSuffix(alias handler, TokenRange)(ref TokenRange trange, Identifier i) {
	switch(trange.front.type) with(TokenType) {
		case OpenBracket :
			// Open Backet can be so many different things !
			assert(0, "Not implemented");
		
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
			assert(0, "Can be a pointer or an expression, or many even a declaration. That is bad !");
		
		default :
			return handler(i);
	}
}

private typeof(handler(null)) parseAmbiguousSuffix(alias handler, TokenRange)(ref TokenRange trange, Type t) {
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

private typeof(handler(null)) parseAmbiguousSuffix(alias handler, TokenRange)(ref TokenRange trange, Expression e) {
	switch(trange.front.type) with(TokenType) {
		case Dot :
			trange.popFront();
			
			auto i = trange.parseQualifiedIdentifier(e.location, e);
			return trange.parseAmbiguousSuffix!ambiguousHandler(i).apply!handler();
		
		default :
			return handler(e);
	}
}

