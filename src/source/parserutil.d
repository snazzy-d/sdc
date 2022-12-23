module source.parserutil;

import source.dlexer;

auto match(Lexer, TokenType)(ref Lexer lexer, TokenType type) {
	auto token = lexer.front;

	if (token.type == type) {
		lexer.popFront();
		return token;
	}

	import std.conv, std.string;
	auto error = token.type == TokenType.Invalid
		? token.error.toString(lexer.context)
		: format!"expected '%s', got '%s'."(to!string(type),
		                                    to!string(token.type));

	import source.exception;
	throw new CompileException(token.location, error);
}

auto unexpectedTokenError(Lexer)(ref Lexer lexer, string expected) {
	auto token = lexer.front;

	import std.conv, std.string;
	auto error = token.type == Lexer.TokenType.Invalid
		? token.error.toString(lexer.context)
		: format!"expected %s, not `%s`."(expected,
		                                  token.toString(lexer.context));

	import source.exception;
	return new CompileException(token.location, error);
}

bool popOnMatch(Lexer, TokenType)(ref Lexer lexer, TokenType type) {
	auto token = lexer.front;
	if (token.type != type) {
		return false;
	}

	lexer.popFront();
	return true;
}

/**
 * Get the matching delimiter
 */
template MatchingDelimiter(TokenType openTokenType) {
	static if (openTokenType == TokenType.OpenParen) {
		alias MatchingDelimiter = TokenType.CloseParen;
	} else static if (openTokenType == TokenType.OpenBrace) {
		alias MatchingDelimiter = TokenType.CloseBrace;
	} else static if (openTokenType == TokenType.OpenBracket) {
		alias MatchingDelimiter = TokenType.CloseBracket;
	} else static if (openTokenType == TokenType.Less) {
		alias MatchingDelimiter = TokenType.Greater;
	} else {
		import std.conv;
		static assert(
			0,
			to!string(openTokenType)
				~ " isn't a token that goes by pair. Use (, {, [, <"
		);
	}
}

/**
 * Pop a range of token until we pop the matchin delimiter.
 * matchin tokens are (), [], <> and {}
 */
void popMatchingDelimiter(TokenType openTokenType)(ref TokenRange trange) {
	auto startLocation = trange.front.location;
	alias closeTokenType = MatchingDelimiter!openTokenType;

	assert(trange.front.type == openTokenType);
	uint level = 1;

	while (level > 0) {
		trange.popFront();

		switch (trange.front.type) {
			case openTokenType:
				level++;
				break;

			case closeTokenType:
				level--;
				break;

			case TokenType.End:
				import source.exception;
				throw new CompileException(startLocation,
				                           "Matching delimiter not found");

			default:
				break;
		}
	}

	assert(trange.front.type == closeTokenType);
	trange.popFront();
}
