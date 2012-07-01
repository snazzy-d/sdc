module d.parser.util;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Tool to lookahead what is after the matching opening token.
 * matchin tokens are (), [], <> and {}
 */
auto lookAfterMatchingDelimiter(TokenType openTokenType)(TokenStream tstream) in {
	assert(tstream.peek.type == openTokenType);
} body {
	static if(openTokenType == TokenType.OpenParen) {
		alias TokenType.CloseParen closeTokenType;
	} else static if(openTokenType == TokenType.OpenBrace) {
		alias TokenType.CloseBrace closeTokenType;
	} else static if(openTokenType == TokenType.OpenBracket) {
		alias TokenType.CloseBracket closeTokenType;
	} else static if(openTokenType == TokenType.Less) {
		alias TokenType.Greater closeTokenType;
	} else {
		static assert(0, tokenToString[openTokenType] ~ " isn't a toke, that goes by pair. Use (, {, [, <");
	}
	
	uint level = 1;
	uint n = 1;
	
	while(level > 0) {
		switch(tstream.lookahead(n).type) {
			case openTokenType :
				level++;
				break;
			
			case closeTokenType :
				level--;
				break;
			
			case TokenType.End :
				assert(0);
			
			default :
				break;
		}
		
		n++;
	}
	
	return tstream.lookahead(n);
}

/**
 * Lookahead if what comes is a type.
 */
bool isType(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.Const, TokenType.Immutable, TokenType.Inout, TokenType.Shared, TokenType.Typeof :
			return true;
		
		case TokenType.Byte, TokenType.Ubyte, TokenType.Short, TokenType.Ushort, TokenType.Int, TokenType.Uint, TokenType.Long, TokenType.Ulong, TokenType.Char, TokenType.Dchar, TokenType.Wchar, TokenType.Void :
			switch(tstream.lookahead(1).type) {
				case TokenType.Asterix, TokenType.OpenBracket :
					return true;
				
				default :
					return false;
			}
		
		default :
			return false;
	}
}

