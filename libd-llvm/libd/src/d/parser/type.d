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
	return parseTypeSuffix!true(tstream, base);
}

Type parseConfirmedType(TokenStream tstream) {
	auto base = parseBasicType(tstream);
	return parseTypeSuffix!false(tstream, base);
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
		
		case TokenType.Shared, TokenType.Scope, TokenType.Ref :
			// TODO: handle shared, scope and ref.
			return processQualifier!(function(Type type) { return type; })();
		
		// Identified types
		case TokenType.Identifier :
			auto identifier = parseIdentifier(tstream);
			location.spanTo(tstream.previous.location);
			return new IdentifierType(location, identifier);
		
		case TokenType.Dot :
			auto identifier = parseDotIdentifier(tstream);
			location.spanTo(tstream.previous.location);
			return new IdentifierType(location, identifier);
		
		case TokenType.Typeof :
			tstream.get();
			return parseTypeof(tstream, location);
		
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
auto parseTypeSuffix(bool isGreedy)(TokenStream tstream, Type type) {
	auto location = type.location;
	
	while(1) {
		switch(tstream.peek.type) {
			case TokenType.Asterix :
				tstream.get();
				location.spanTo(tstream.previous.location);
				
				type = new PointerType(location, type);
				break;
				
			case TokenType.OpenBracket :
				type = parseBracket(tstream, type);
				
				break;
			
			case TokenType.Dot :
				if(tstream.lookahead(1).type != TokenType.Identifier) return type;
				
				static if(!isGreedy) {
					import d.parser.util;
					if(!getConfirmedTypeIndex(tstream)) {
						return type;
					}
				}
				
				tstream.get();
				auto identifier = parseQualifiedIdentifier(tstream, type.location, type);
				location.spanTo(tstream.previous.location);
			
				type = new IdentifierType(location, identifier);
				
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

Type parseBracket(TokenStream tstream, Type type) {
	import d.parser.util;
	
	auto location = type.location;
	
	// -1 because we the match the opening [
	auto matchingBracket = getMatchingDelimiterIndex!(TokenType.OpenBracket)(tstream) - 1;
	match(tstream, TokenType.OpenBracket);
	
	if(matchingBracket == 0) {
		location.spanTo(tstream.get().location);
		return new SliceType(location, type);
	} else if(getConfirmedTypeIndex(tstream) == matchingBracket) {
		auto keyType = parseType(tstream);
		location.spanTo(match(tstream, TokenType.CloseBracket).location);
		return new AssociativeArrayType(location, type, keyType);
	} else if(getTypeIndex(tstream) == matchingBracket) {
		// TODO: manage ambiguity.
		auto keyType = parseType(tstream);
		
		import sdc.terminal;
		outputCaretDiagnostics(keyType.location, "ambiguity");
		
		location.spanTo(match(tstream, TokenType.CloseBracket).location);
		return new AssociativeArrayType(location, type, keyType);
	} else {
		auto value = parseExpression(tstream);
		location.spanTo(match(tstream, TokenType.CloseBracket).location);
		return new StaticArrayType(location, type, value);
	}
}

