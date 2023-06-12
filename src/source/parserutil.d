module source.parserutil;

auto match(Lexer, TokenType)(ref Lexer lexer, TokenType type) {
	auto token = lexer.front;

	if (token.type == type) {
		lexer.popFront();
		return token;
	}

	import std.conv;
	throw unexpectedTokenError(lexer, to!string(type));
}

auto unexpectedTokenError(Lexer)(ref Lexer lexer, string expected) {
	auto token = lexer.front;

	import std.format;
	string error;
	switch (token.type) {
		case Lexer.TokenType.Invalid:
			error = token.error.toString(lexer.context);
			break;

		case Lexer.TokenType.End:
			auto found = token.location.isMixin()
				? "the end of the input"
				: "the end of the file";
			error = format!"expected %s, not %s."(expected, found);
			break;

		default:
			error =
				format!"expected %s, not `%s`."(expected,
				                                token.toString(lexer.context));
	}

	import source.exception;
	if (lexer.reachedEOF()) {
		return new IncompleteInputException(token.location, error);
	}

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
template MatchingDelimiter(alias openTokenType) {
	alias TokenType = typeof(openTokenType);

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
void popMatchingDelimiter(alias openTokenType, Lexer)(ref Lexer lexer) {
	auto startLocation = lexer.front.location;
	alias closeTokenType = MatchingDelimiter!openTokenType;

	assert(lexer.front.type == openTokenType);
	uint level = 1;

	while (level > 0) {
		lexer.popFront();

		switch (lexer.front.type) {
			case openTokenType:
				level++;
				break;

			case closeTokenType:
				level--;
				break;

			case Lexer.TokenType.End:
				import source.exception;
				throw new CompileException(startLocation,
				                           "Matching delimiter not found");

			default:
				break;
		}
	}

	assert(lexer.front.type == closeTokenType);
	lexer.popFront();
}

unittest {
	import source.context, source.dlexer;
	auto context = new Context();

	auto makeTestLexer(string s) {
		import source.location;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		return lex(base, context);
	}

	auto checkIncompleteInput(string s, string expectedMsg) {
		auto lex = makeTestLexer(s).withComments(true);

		import source.parserutil;
		import source.exception;
		import std.format;
		lex.match(TokenType.Begin);

		try {
			throw unexpectedTokenError(lex, null);
		} catch (IncompleteInputException e) {
			assert(
				e.msg == expectedMsg,
				format!"Error message mismatch: expected `%s`, got `%s`"(
					expectedMsg, e.msg)
			);
			return;
		} catch (Throwable t) {
			assert(
				false,
				format!"Didn't throw IncompleteInputException. Instead got %s"(
					t)
			);
		}

		assert(false, "Didn't throw IncompleteInputException");
	}

	// EOF in the middle of the token
	checkIncompleteInput("/*/", "Comment must end with `*/`.");
	checkIncompleteInput(
		"\"", "Expected '\"' to end string literal, not the end of the input.");
	checkIncompleteInput(
		"'", "Expected a character literal, not the end of the input.");
	checkIncompleteInput("0b", "0b is not a valid binary literal.");
	checkIncompleteInput("0x", "0x is not a valid hexmadecimal literal.");
	checkIncompleteInput("0o", "`o` is not a valid suffix.");
	checkIncompleteInput("1e", "Float literal is missing exponent.");

	// EOF instead of a token
	checkIncompleteInput("", "expected , not the end of the input.");
}
