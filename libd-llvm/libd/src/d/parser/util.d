module d.parser.util;

import d.parser.base;
import d.parser.expression;
import d.parser.type;

/**
 * Get the matching delimiter
 */
template MatchingDelimiter(TokenType openTokenType) {
	static if(openTokenType == TokenType.OpenParen) {
		alias MatchingDelimiter = TokenType.CloseParen;
	} else static if(openTokenType == TokenType.OpenBrace) {
		alias MatchingDelimiter = TokenType.CloseBrace;
	} else static if(openTokenType == TokenType.OpenBracket) {
		alias MatchingDelimiter = TokenType.CloseBracket;
	} else static if(openTokenType == TokenType.Less) {
		alias MatchingDelimiter = TokenType.Greater;
	} else {
		import std.conv;
		static assert(0, to!string(openTokenType) ~ " isn't a token that goes by pair. Use (, {, [, <");
	}
}

/**
 * Pop a range of token until we pop the matchin delimiter.
 * matchin tokens are (), [], <> and {}
 */
void popMatchingDelimiter(TokenType openTokenType, TokenRange)(ref TokenRange trange) {
	auto startLocation = trange.front.location;
	alias closeTokenType = MatchingDelimiter!openTokenType;
	
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
				import d.exception;
				throw new CompileException(startLocation, "Matching delimiter not found");
			
			default :
				break;
		}
	}
	
	assert(trange.front.type == closeTokenType);
	trange.popFront();
}

