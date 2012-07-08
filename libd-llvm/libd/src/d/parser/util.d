module d.parser.util;

import d.parser.base;
import d.parser.expression;
import d.parser.type;

import sdc.tokenstream;
import sdc.location;

import std.range;

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

/**
 * Count how many tokens does the type to be parsed contains.
 * return 0 if no type is parsed.
 */
uint getType(TokenRange)(ref const TokenRange trange) if(isTokenRange!TokenRange) {
	auto start = trange.save;
	auto lookahead = start.save;
	
	uint confirmed;
	return lookahead.popType!TokenRange(start, confirmed);
}

/**
 * Count how many tokens belong to a type with no ambiguity.
 */
uint getConfirmedType(TokenRange)(ref const TokenRange trange) if(isTokenRange!TokenRange) {
	auto start = trange.save;
	auto lookahead = start.save;
	
	uint confirmed;
	lookahead.popType!TokenRange(start, confirmed);
	return confirmed;
}

/**
 * Branch to the right code depending if we have a type, an expression or something ambiguous.
 */
auto proceedAsTypeOrExpression(alias handler, TokenRange)(ref TokenRange trange, uint delimiter) if(isTokenRange!TokenRange) {
	auto lookahead = trange.save;
	
	uint confirmed;
	uint typeIndex = lookahead.popType(trange, confirmed);
	
	if(confirmed == delimiter) {
		return handler(trange.parseType());
	} else if(typeIndex == delimiter) {
		import d.ast.identifier;
		import d.parser.identifier;
		
		auto type = trange.parseType();
		
		import sdc.terminal;
		outputCaretDiagnostics(type.location, "ambiguity");
		
		// TODO: handle ambiguous case instead of type.
		return handler(type);
	} else {
		return handler(trange.parseExpression());
	}
}

private uint popType(TokenRange)(ref TokenRange trange, ref const TokenRange start, out uint confirmed) {
	switch(trange.front.type) {
		case TokenType.Const, TokenType.Immutable, TokenType.Inout, TokenType.Shared :
			trange.popFront();
			
			switch(trange.front.type) {
				case TokenType.OpenParen :
					trange.popMatchingDelimiter!(TokenType.OpenParen)();
					
					confirmed = trange - start;
					
					return trange.getPostfixTypeIndex(start, confirmed);
				
				case TokenType.Identifier :
					auto lookahead = trange.save;
					lookahead.popFront();
					if(lookahead.front.type != TokenType.Assign) goto default;
					
					return trange - start;
				
				default :
					confirmed = trange - start;
					return trange.popType(start, confirmed);
			}
		
		case TokenType.Typeof :
			trange.popFront();
			trange.popMatchingDelimiter!(TokenType.OpenParen)();
			
			confirmed = trange - start;
			
			return trange.getPostfixTypeIndex(start, confirmed);
		
		case TokenType.Byte, TokenType.Ubyte, TokenType.Short, TokenType.Ushort, TokenType.Int, TokenType.Uint, TokenType.Long, TokenType.Ulong, TokenType.Char, TokenType.Wchar, TokenType.Dchar, TokenType.Float, TokenType.Double, TokenType.Real, TokenType.Bool, TokenType.Void :
			trange.popFront();
			confirmed = trange - start;
			
			return trange.getPostfixTypeIndex(start, confirmed);
		
		case TokenType.Identifier :
			trange.popFront();
			return trange.getPostfixTypeIndex(start, confirmed);
		
		case TokenType.Dot :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type != TokenType.Identifier) return 0;
			
			lookahead.popFront();
			return lookahead.getPostfixTypeIndex(start, confirmed);
		
		case TokenType.This, TokenType.Super :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type != TokenType.Dot) return 0;
			
			lookahead.popFront();
			if(lookahead.front.type != TokenType.Identifier) return 0;
			
			lookahead.popFront();
			return trange.getPostfixTypeIndex(lookahead, confirmed);
		
		default :
			return 0;
	}
}

private uint getPostfixTypeIndex(TokenRange)(ref TokenRange trange, ref const TokenRange start, ref uint confirmed) in {
	assert((trange - start) > 0);
} body {
	while(1) {
		switch(trange.front.type) {
			case TokenType.Asterix :
				// type* can only be a pointer to type.
				if((trange - start) == confirmed) {
					confirmed++;
				}
				
				trange.popFront();
				break;
			
			case TokenType.OpenBracket :
				auto matchingBracket = trange.save;
				matchingBracket.popMatchingDelimiter!(TokenType.OpenBracket)();
				
				// If it is a slice, return.
				auto lookahead = trange.save;
				lookahead.popFront();
				while((matchingBracket - lookahead) > 1) {
					switch(lookahead.front.type) {
						case TokenType.DoubleDot :
							return trange - start;
						
						case TokenType.OpenBracket :
							lookahead.popMatchingDelimiter!(TokenType.OpenBracket)();
							break;
						
						default :
							lookahead.popFront();
							break;
					}
				}
				
				// We now are sure to have a potential type.
				import std.range;
				scope(success) popFrontN(trange, matchingBracket - trange);
				
				// Type[anything] is a type.
				if((trange - start) == confirmed) {
					confirmed = (matchingBracket - start);
					break;
				}
				
				// Anything[Type] is also a type.
				trange.popFront();
				auto typeStart = trange.save;
				
				uint confirmedCandidate;
				trange.popType(typeStart, confirmedCandidate);
				if(confirmedCandidate == (matchingBracket - typeStart - 1)) {
					confirmed = (matchingBracket - start);
				}
				
				break;
			
			case TokenType.Dot :
				auto lookahead = trange.save;
				lookahead.popFront();
				if(lookahead.front.type != TokenType.Identifier) return trange - start;
				
				trange.popFront();
				trange.popFront();
				break;
			
			case TokenType.Function, TokenType.Delegate :
				// This is a function/delegate litteral.
				auto lookahead = trange.save;
				lookahead.popFront();
				if(lookahead.front.type != TokenType.Identifier) return trange - start;
				
				trange.popMatchingDelimiter!(TokenType.OpenParen)();
				confirmed = trange - start;
				break;
			
			// TODO: templates instanciation.
			
			default :
				return trange - start;
		}
	}
}

/**
 * Check if we are facing a declaration.
 */
bool isDeclaration(TokenRange)(ref const TokenRange trange) if(isTokenRange!TokenRange) {
	switch(trange.front.type) {
		case TokenType.Auto, TokenType.Import, TokenType.Interface, TokenType.Class, TokenType.Struct, TokenType.Union, TokenType.Enum, TokenType.Template, TokenType.Alias, TokenType.Extern :
			return true;
		
		default :
			auto lookahead = trange.save;
			uint confirmed;
			if(lookahead.popType(trange, confirmed)) {
				return lookahead.front.type == TokenType.Identifier;
			}
			
			return false;
	}
}

