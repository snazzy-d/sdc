module sdc.parser.type2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base;
import sdc.ast.type2;

Type parseType(TokenStream tstream) {
	return parseBasicType(tstream);
}

auto parseBasicType(TokenStream tstream) {
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
		case TokenType.Const :
			return processQualifier!(function(Type type) { return type.makeConst(); })();
		case TokenType.Immutable :
			return processQualifier!(function(Type type) { return type.makeImmutable(); })();
		case TokenType.Mutable :
			return processQualifier!(function(Type type) { return type.makeMutable(); })();
		case TokenType.Inout :
			return processQualifier!(function(Type type) { return type.makeInout(); })();
		case TokenType.Identifier :
			return parseIdentifierType(tstream, tstream.get().value);
		case TokenType.Dot :
			tstream.get();
			return parseIdentifierType(tstream, "");
		case TokenType.Typeof :
			// TODO: Handle typeof.
			assert(0);
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

auto parseIdentifierType(TokenStream tstream, string name) {
	string[] identifiers = [name];
	auto location = tstream.peek.location;
	
	while(tstream.peek.type == TokenType.Dot) {
		tstream.get();
		identifiers ~= match(tstream, TokenType.Identifier).value;
	}
	
	location.spanTo(tstream.previous.location);
	
	return new IdentifierType(location, identifiers);
}

