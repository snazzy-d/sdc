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
	return tstream.lookahead(getMatchingDelimiterIndex!openTokenType(tstream) + 1);
}

private uint getMatchingDelimiterIndex(TokenType openTokenType)(TokenStream tstream, uint n = 0) in {
	assert(tstream.lookahead(n).type == openTokenType);
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
	
	while(level > 0) {
		n++;
		
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
	}
	
	return n;
}

/**
 * Count how many tokens does the type to be parsed contains.
 * return 0 if no type is parsed.
 */
uint getTypeSize(TokenStream tstream) {
	return getTypeSize(tstream, 0);
}

private uint getTypeSize(TokenStream tstream, uint n) {
	switch(tstream.lookahead(n).type) {
		case TokenType.Const, TokenType.Immutable, TokenType.Inout, TokenType.Shared :
			switch(tstream.lookahead(n + 1).type) {
				case TokenType.OpenParen :
					n = getMatchingDelimiterIndex!(TokenType.OpenParen)(tstream, n + 1);
					if(tstream.lookahead(n).type != TokenType.CloseParen) return 0;
					
					return getPostfixTypeSize(tstream, n + 1);
				
				case TokenType.Identifier :
					if(tstream.lookahead(n + 2).type != TokenType.Assign) goto default;
					
					return n + 1;
				
				default :
					return getTypeSize(tstream, n + 1);
			}
		
		case TokenType.Typeof :
			if(tstream.lookahead(n + 1).type != TokenType.OpenParen) return 0;
			n = getMatchingDelimiterIndex!(TokenType.OpenParen)(tstream, n + 1);
			if(tstream.lookahead(n).type != TokenType.CloseParen) return 0;
			
			return getPostfixTypeSize(tstream, n + 1);
		
		case TokenType.Byte, TokenType.Ubyte, TokenType.Short, TokenType.Ushort, TokenType.Int, TokenType.Uint, TokenType.Long, TokenType.Ulong, TokenType.Char, TokenType.Wchar, TokenType.Dchar, TokenType.Float, TokenType.Double, TokenType.Real, TokenType.Bool, TokenType.Void :
			return getPostfixTypeSize(tstream, n + 1);
		
		case TokenType.Identifier :
			return getPostfixTypeSize(tstream, n + 1);
		
		case TokenType.Dot :
			if(tstream.lookahead(n + 1).type != TokenType.Identifier) return 0;
			
			return getPostfixTypeSize(tstream, n + 2);
		
		case TokenType.This, TokenType.Super :
			if(tstream.lookahead(n + 1).type != TokenType.Dot) return 0;
			if(tstream.lookahead(n + 2).type != TokenType.Identifier) return 0;
			
			return getPostfixTypeSize(tstream, n + 3);
		
		default :
			return 0;
	}
}

private uint getPostfixTypeSize(TokenStream tstream, uint n) in {
	assert(n > 0);
} body {
	while(1) {
		switch(tstream.lookahead(n).type) {
			case TokenType.Asterix :
				n++;
				break;
			
			case TokenType.OpenBracket :
				// TODO: check for slice.
				uint candidate = getMatchingDelimiterIndex!(TokenType.OpenBracket)(tstream, n);
				if(tstream.lookahead(n).type != TokenType.CloseBracket) return n;
				
				n = candidate + 1;
				break;
			
			case TokenType.Dot :
				if(tstream.lookahead(n + 1).type != TokenType.Identifier) return n + 1;
				
				n += 2;
				break;
			
			// TODO: templates instanciation.
			
			default :
				return n;
		}
	}
}

/**
 * Check if we are facing a declaration.
 */
bool isDeclaration(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.Auto, TokenType.Import, TokenType.Interface, TokenType.Class, TokenType.Struct, TokenType.Union, TokenType.Enum, TokenType.Template :
			return true;
		
		default :
			return tstream.lookahead(getTypeSize(tstream)).type == TokenType.Identifier;
	}
}

