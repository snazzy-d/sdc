module d.parser.util;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

auto lookAfterMatchingDelimiter(TokenType openTokenType)(TokenStream tstream) {
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
	
	assert(tstream.peek.type == openTokenType);
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

