module d.parser.type;

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.parser.dfunction;
import d.parser.expression;
import d.parser.identifier;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

Type parseType(TokenStream tstream) {
	auto base = parseBasicType(tstream);
	return parseTypeSuffix(tstream, base);
}

auto parseBasicType(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	auto processQualifier(alias qualifyType)() {
		tstream.get();
		
		if(tstream.peek.type == TokenType.OpenParen) {
			tstream.get();
			auto type = parseType(tstream);
			match(tstream, TokenType.CloseParen);
			
			return qualifyType(type);
		}
		
		return qualifyType(parseType(tstream));
	}
	
	switch(tstream.peek.type) {
		// Types qualifiers
		case TokenType.Const :
			return processQualifier!(function(Type type) { return type.makeConst(); })();
		case TokenType.Immutable :
			return processQualifier!(function(Type type) { return type.makeImmutable(); })();
		case TokenType.Mutable :
			return processQualifier!(function(Type type) { return type.makeMutable(); })();
		case TokenType.Inout :
			return processQualifier!(function(Type type) { return type.makeInout(); })();
		
		// Identified types
		case TokenType.Identifier :
			auto identifier = parseIdentifier(tstream);
			location.spanTo(tstream.previous.location);
			return new IdentifierType(location, identifier);
		case TokenType.Dot :
			tstream.get();
			auto identifier = parseDotIdentifier(tstream, location);
			location.spanTo(tstream.previous.location);
			return new IdentifierType(location, identifier);
		case TokenType.Typeof :
			tstream.get();
			auto type = parseTypeof(tstream, location);
			if(tstream.peek.type == TokenType.Dot) {
				tstream.get();
				
				auto identifier = parseQualifiedIdentifier(tstream, location, type);
				location.spanTo(tstream.peek.location);
				
				type = new IdentifierType(location, identifier);
			}
			
			return type;
		case TokenType.This :
			tstream.get();
			auto thisExpression = new ThisExpression(location);
			match(tstream, TokenType.Dot);
			auto identifier = parseQualifiedIdentifier(tstream, location, thisExpression);
			location.spanTo(tstream.previous.location);
			return new IdentifierType(location, identifier);
		case TokenType.Super :
			tstream.get();
			auto superExpression = new SuperExpression(location);
			match(tstream, TokenType.Dot);
			auto identifier = parseQualifiedIdentifier(tstream, location, superExpression);
			location.spanTo(tstream.previous.location);
			return new IdentifierType(location, identifier);
		
		// Basic types
		case TokenType.Bool :
			tstream.get();
			return new BuiltinType!bool(location);
		case TokenType.Byte :
			tstream.get();
			return new BuiltinType!byte(location);
		case TokenType.Ubyte :
			tstream.get();
			return new BuiltinType!ubyte(location);
		case TokenType.Short :
			tstream.get();
			return new BuiltinType!short(location);
		case TokenType.Ushort :
			tstream.get();
			return new BuiltinType!ushort(location);
		case TokenType.Int :
			tstream.get();
			return new BuiltinType!int(location);
		case TokenType.Uint :
			tstream.get();
			return new BuiltinType!uint(location);
		case TokenType.Long :
			tstream.get();
			return new BuiltinType!long(location);
		case TokenType.Ulong :
			tstream.get();
			return new BuiltinType!ulong(location);
/*		case TokenType.Cent :
			tstream.get();
			return new BuiltinType!cent(location);
		case TokenType.Ucent :
			tstream.get();
			return new BuiltinType!ucent(location);	*/
		case TokenType.Char :
			tstream.get();
			return new BuiltinType!char(location);
		case TokenType.Wchar :
			tstream.get();
			return new BuiltinType!wchar(location);
		case TokenType.Dchar :
			tstream.get();
			return new BuiltinType!dchar(location);
		case TokenType.Float :
			tstream.get();
			return new BuiltinType!float(location);
		case TokenType.Double :
			tstream.get();
			return new BuiltinType!double(location);
		case TokenType.Real :
			tstream.get();
			return new BuiltinType!real(location);
		case TokenType.Void :
			tstream.get();
			return new BuiltinType!void(location);
		
		default :
			match(tstream, TokenType.Begin);
			// TODO: handle.
			// Erreur, basic type expected.
			assert(0);
	}
}

/**
 * Parse typeof(...)
 */
auto parseTypeof(TokenStream tstream, Location location) {
	BasicType type;
	
	match(tstream, TokenType.OpenParen);
	
	if(tstream.peek.type == TokenType.Return) {
		tstream.get();
		location.spanTo(tstream.peek.location);
		
		type = new ReturnType(location);
	} else {
		auto e = parseExpression(tstream);
		location.spanTo(tstream.peek.location);
		
		type = new TypeofType(location, e);
	}
	
	match(tstream, TokenType.CloseParen);
	
	return type;
}

/**
 * Parse *, [ ... ] and function/delegate types.
 */
auto parseTypeSuffix(TokenStream tstream, Type type) {
	auto location = type.location;
	
	while(1) {
		switch(tstream.peek.type) {
			case TokenType.Asterix :
				tstream.get();
				location.spanTo(tstream.previous.location);
				
				type = new PointerType(location, type);
				break;
				
			case TokenType.OpenBracket :
				tstream.get();
				if(tstream.peek.type == TokenType.CloseBracket) {
					tstream.get();
					location.spanTo(tstream.previous.location);
					
					type = new SliceType(location, type);
				} else {
					// TODO: figure out what to do with that. Associative array or static arrays ?
					match(tstream, TokenType.Begin);
					assert(0);
				}
				
				break;
			case TokenType.Function :
				tstream.get();
				bool isVariadic;
				auto parameters = parseParameters(tstream, isVariadic);
				location.spanTo(tstream.previous.location);
				
				// TODO: parse postfix attributes.
				return new FunctionType(location, type, parameters, isVariadic);
			
			case TokenType.Delegate :
				tstream.get();
				bool isVariadic;
				auto parameters = parseParameters(tstream, isVariadic);
				location.spanTo(tstream.previous.location);
				
				// TODO: parse postfix attributes and storage class.
				return new DelegateType(location, type, parameters, isVariadic);
			
			default :
				return type;
		}
	}
}

