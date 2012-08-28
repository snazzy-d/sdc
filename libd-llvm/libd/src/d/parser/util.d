module d.parser.util;

import d.parser.base;
import d.parser.expression;
import d.parser.type;

/**
 * Pop a range of token until we pop the matchin delimiter.
 * matchin tokens are (), [], <> and {}
 */
void popMatchingDelimiter(TokenType openTokenType, TokenRange)(ref TokenRange trange) {
	static if(openTokenType == TokenType.OpenParen) {
		alias TokenType.CloseParen closeTokenType;
	} else static if(openTokenType == TokenType.OpenBrace) {
		alias TokenType.CloseBrace closeTokenType;
	} else static if(openTokenType == TokenType.OpenBracket) {
		alias TokenType.CloseBracket closeTokenType;
	} else static if(openTokenType == TokenType.Less) {
		alias TokenType.Greater closeTokenType;
	} else {
		static assert(0, tokenToString[openTokenType] ~ " isn't a token that goes by pair. Use (, {, [, <");
	}
	
	assert(trange.front.type == openTokenType);
	uint level = 1;
	
	while(level > 0) {
		trange.popFront();
		
		switch(trange.front.type) {
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
	}
	
	assert(trange.front.type == closeTokenType);
	trange.popFront();
}

