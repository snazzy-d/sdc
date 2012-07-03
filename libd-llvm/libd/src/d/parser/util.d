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
		static assert(0, tokenToString[openTokenType] ~ " isn't a token that goes by pair. Use (, {, [, <");
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
	
	assert(tstream.lookahead(n).type == closeTokenType);
	return n;
}

/**
 * Count how many tokens does the type to be parsed contains.
 * return 0 if no type is parsed.
 */
uint getTypeIndex(TokenStream tstream) {
	uint confirmed;
	return getTypeIndex(tstream, 0, confirmed);
}

/**
 * Count how many tokens belong to a type with no ambiguity.
 */
uint getConfirmedTypeIndex(TokenStream tstream) {
	uint confirmed;
	getTypeIndex(tstream, 0, confirmed);
	return confirmed;
}

private uint getTypeIndex(TokenStream tstream, uint index, out uint confirmed) {
	switch(tstream.lookahead(index).type) {
		case TokenType.Const, TokenType.Immutable, TokenType.Inout, TokenType.Shared :
			index++;
			
			switch(tstream.lookahead(index).type) {
				case TokenType.OpenParen :
					confirmed = index = getMatchingDelimiterIndex!(TokenType.OpenParen)(tstream, index);
					
					return getPostfixTypeIndex(tstream, index, confirmed);
				
				case TokenType.Identifier :
					if(tstream.lookahead(index + 1).type != TokenType.Assign) goto default;
					
					return index;
				
				default :
					confirmed = index;
					return getTypeIndex(tstream, index, confirmed);
			}
		
		case TokenType.Typeof :
			index++;
			
			if(tstream.lookahead(index).type != TokenType.OpenParen) return 0;
			confirmed = index = getMatchingDelimiterIndex!(TokenType.OpenParen)(tstream, index) + 1;
			
			return getPostfixTypeIndex(tstream, index, confirmed);
		
		case TokenType.Byte, TokenType.Ubyte, TokenType.Short, TokenType.Ushort, TokenType.Int, TokenType.Uint, TokenType.Long, TokenType.Ulong, TokenType.Char, TokenType.Wchar, TokenType.Dchar, TokenType.Float, TokenType.Double, TokenType.Real, TokenType.Bool, TokenType.Void :
			confirmed = ++index;
			return getPostfixTypeIndex(tstream, index, confirmed);
		
		case TokenType.Identifier :
			return getPostfixTypeIndex(tstream, index + 1, confirmed);
		
		case TokenType.Dot :
			if(tstream.lookahead(index + 1).type != TokenType.Identifier) return 0;
			
			return getPostfixTypeIndex(tstream, index + 2, confirmed);
		
		case TokenType.This, TokenType.Super :
			if(tstream.lookahead(index + 1).type != TokenType.Dot) return 0;
			if(tstream.lookahead(index + 2).type != TokenType.Identifier) return 0;
			
			return getPostfixTypeIndex(tstream, index + 3, confirmed);
		
		default :
			return 0;
	}
}

private uint getPostfixTypeIndex(TokenStream tstream, uint index, ref uint confirmed) in {
	assert(index > 0);
} body {
	while(1) {
		switch(tstream.lookahead(index).type) {
			case TokenType.Asterix :
				// type* can only be a pointer to type.
				if(confirmed == index) {
					confirmed++;
				}
				
				index++;
				break;
			
			case TokenType.OpenBracket :
				// Type[anything] is a type.
				uint matchingBracket = getMatchingDelimiterIndex!(TokenType.OpenBracket)(tstream, index);
				if(confirmed == index) {
					index = confirmed = matchingBracket + 1;
					break;
				}
				
				// If it is a slice, return.
				for(uint i = index + 1; i < matchingBracket; ++i) {
					switch(tstream.lookahead(i).type) {
						case TokenType.DoubleDot :
							return index;
						
						case TokenType.OpenBracket :
							i = getMatchingDelimiterIndex!(TokenType.OpenBracket)(tstream, index) + 1;
							break;
						
						default :
							continue;
					}
				}
				
				index = matchingBracket + 1;
				
				// Associative arrays are confirmed types.
				uint confirmedCandidate;
				getTypeIndex(tstream, index + 1, confirmedCandidate);
				if(confirmedCandidate == matchingBracket) {
					confirmed = index;
				}
				
				break;
			
			case TokenType.Dot :
				if(tstream.lookahead(index + 1).type != TokenType.Identifier) return index;
				
				index += 2;
				break;
			
			// TODO: templates instanciation.
			
			default :
				return index;
		}
	}
}

/**
 * Check if we are facing a declaration.
 */
bool isDeclaration(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.Auto, TokenType.Import, TokenType.Interface, TokenType.Class, TokenType.Struct, TokenType.Union, TokenType.Enum, TokenType.Template, TokenType.Alias :
			return true;
		
		default :
			uint typeIndex = getTypeIndex(tstream);
			if(typeIndex) {
				return tstream.lookahead(typeIndex).type == TokenType.Identifier;
			}
			
			return false;
	}
}

