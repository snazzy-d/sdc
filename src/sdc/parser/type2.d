module sdc.parser.type2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.expression2;
import sdc.parser.identifier2;
import sdc.ast.declaration2;
import sdc.ast.expression2;
import sdc.ast.type2;

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
			return builtinType!bool;
		case TokenType.Byte :
			tstream.get();
			return builtinType!byte;
		case TokenType.Ubyte :
			tstream.get();
			return builtinType!ubyte;
		case TokenType.Short :
			tstream.get();
			return builtinType!short;
		case TokenType.Ushort :
			tstream.get();
			return builtinType!ushort;
		case TokenType.Int :
			tstream.get();
			return builtinType!int;
		case TokenType.Uint :
			tstream.get();
			return builtinType!uint;
		case TokenType.Long :
			tstream.get();
			return builtinType!long;
		case TokenType.Ulong :
			tstream.get();
			return builtinType!ulong;
/*		case TokenType.Cent :
			tstream.get();
			return builtinType!cent;
		case TokenType.Ucent :
			tstream.get();
			return builtinType!ucent;	*/
		case TokenType.Char :
			tstream.get();
			return builtinType!char;
		case TokenType.Wchar :
			tstream.get();
			return builtinType!wchar;
		case TokenType.Dchar :
			tstream.get();
			return builtinType!dchar;
		case TokenType.Float :
			tstream.get();
			return builtinType!float;
		case TokenType.Double :
			tstream.get();
			return builtinType!double;
		case TokenType.Real :
			tstream.get();
			return builtinType!real;
		case TokenType.Void :
			tstream.get();
			return builtinType!void;
		
		default :
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
					assert(0);
				}
				
				break;
			case TokenType.Function :
				auto parameters = parseParameters(tstream);
				location.spanTo(tstream.previous.location);
				return new FunctionType(location, type, parameters);
			
			case TokenType.Delegate :
				auto parameters = parseParameters(tstream);
				location.spanTo(tstream.previous.location);
				return new DelegateType(location, type, parameters);
			
			default :
				return type;
		}
	}
}

/**
 * Parse function and delegate parameters.
 */
auto parseParameters(TokenStream tstream) {
	match(tstream, TokenType.OpenParen);
	
	Parameter[] parameters;
	
	if(tstream.peek.type != TokenType.CloseParen) {
		parameters ~= parseParameter(tstream);
		
		while(tstream.peek.type == TokenType.Comma) {
			tstream.get();
			
			parameters ~= parseParameter(tstream);
		}
	}
	
	match(tstream, TokenType.CloseParen);
	
	return parameters;
}

auto parseParameter(TokenStream tstream) {
	// TODO: parse storage class
	// TODO: handle variadic functions
	
	auto type = parseType(tstream);
	
	if(tstream.peek.type == TokenType.Identifier) {
		auto location = type.location;
		
		string name = tstream.get().value;
		
		if(tstream.peek.type == TokenType.Assign) {
			tstream.get();
			
			auto expression = parseAssignExpression(tstream);
			
			location.spanTo(tstream.previous.location);
			return new ValueParameter(location, type, name, expression);
		}
		
		location.spanTo(tstream.previous.location);
		return new NamedParameter(location, type, name);
	}
	
	return new Parameter(type.location, type);
}

