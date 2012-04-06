module sdc.parser.type2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.expression2;
import sdc.parser.identifier2;
import sdc.ast.type2;

Type parseType(TokenStream tstream) {
	return parseBasicType(tstream);
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
			assert(0);
		case TokenType.Typeof :
			tstream.get();
			return parseTypeof(tstream, location);
		
		// Basic types
		case TokenType.Bool :
			return basicType!bool;
		case TokenType.Byte :
			return basicType!byte;
		case TokenType.Ubyte :
			return basicType!ubyte;
		case TokenType.Short :
			return basicType!short;
		case TokenType.Ushort :
			return basicType!ushort;
		case TokenType.Int :
			return basicType!int;
		case TokenType.Uint :
			return basicType!uint;
		case TokenType.Long :
			return basicType!long;
		case TokenType.Ulong :
			return basicType!ulong;
/*		case TokenType.Cent :
			return basicType!cent;
		case TokenType.Ucent :
			return basicType!ucent;	*/
		case TokenType.Char :
			return basicType!char;
		case TokenType.Wchar :
			return basicType!wchar;
		case TokenType.Dchar :
			return basicType!dchar;
		case TokenType.Float :
			return basicType!float;
		case TokenType.Double :
			return basicType!double;
		case TokenType.Real :
			return basicType!real;
/*		case TokenType.Ifloat :
			return basicType!ifloat;
		case TokenType.Idouble :
			return basicType!idouble;
		case TokenType.Ireal :
			return basicType!ireal;
		case TokenType.Cfloat :
			return basicType!cfloat;
		case TokenType.Cdouble :
			return basicType!cdouble;
		case TokenType.Creal :
			return basicType!creal;	*/
		case TokenType.Void :
			return basicType!void;
		
		default :
			// TODO: handle.
			assert(0);
	}
}

/**
 * Parse typeof(...)
 */
auto parseTypeof(TokenStream tstream, Location location) {
	QualifierType type;
	
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
	
	if(tstream.peek.type == TokenType.Dot) {
		tstream.get();
		
		auto identifier = parseQualifiedIdentifier(tstream, location, type);
		location.spanTo(tstream.peek.location);
		
		type = new IdentifierType(location, identifier);
	}
	
	return type;
}

