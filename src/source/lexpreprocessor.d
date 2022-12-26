module source.lexpreprocessor;

mixin template LexPreprocessorImpl(Token, alias TokenHandlers,
                                   alias IdentifierHandlers) {
	void popPreprocessorWhiteSpaces() {
		popHorizontalWhiteSpaces();
	}

	Token getPreprocessorComment(uint begin, Token end)
			in(end.type == TokenType.End) {
		auto location =
			base.getWithOffsets(begin, begin).spanTo(end.location.start);

		return Token.getComment!"#"(location);
	}

	Token getNextPreprocessorToken() {
		static getMap() {
			auto ret = getLexerMap();

			// Generate a # operator so we don't
			// preprocess while we preprocess.
			ret["#"] = "lexOperator";

			return ret;
		}

		while (true) {
			popPreprocessorWhiteSpaces();

			// Terminate at the end of the line.
			const begin = index;
			if (popLineBreak()) {
				return Token.getEnd(base.getWithOffsets(begin, index));
			}

			import source.lexermixin;
			// pragma(msg, lexerMixin(getMap()));
			mixin(lexerMixin(getMap()));
		}
	}

	Token popPreprocessorDirective(uint begin) {
		auto lookahead = getLookahead();
		scope(exit) {
			index = lookahead.index;
		}

		while (true) {
			auto lt = lookahead.getNextPreprocessorToken();
			switch (lt.type) with (TokenType) {
				case Invalid:
					// Bubble up errors.
					return lt;

				case End:
					return getPreprocessorComment(begin, lt);

				default:
					break;
			}
		}
	}

	Token lexPreprocessorDirective(string s : "#")() {
		uint l = s.length;
		uint begin = index - l;

		if (!preprocessDirectives) {
			return popPreprocessorDirective(begin);
		}

		auto lookahead = getLookahead().withLiteralDecoding();
		scope(exit) {
			index = lookahead.index;
		}

		auto i = lookahead.getNextPreprocessorToken();
		static foreach (T, fun; TokenHandlers) {
			if (i.type == T) {
				import std.format;
				return mixin(format!"lookahead.%s(begin, i)"(fun));
			}
		}

		// If this is a # alone, then we got a hash operator.
		if (i.type == TokenType.End) {
			return lexOperator!"#"();
		}

		if (i.type == TokenType.Identifier) {
			static foreach (I, fun; IdentifierHandlers) {
				if (i.name == BuiltinName!I) {
					import std.format;
					return mixin(format!"lookahead.%s(begin, i)"(fun));
				}
			}
		}

		import std.format;
		return getError(
			i.location,
			format!"C preprocessor directive `#%s` is not supported."(
				i.toString(context))
		);
	}

	auto skipPreprocessorDirective(string s : "#")(Token ld) {
		return skipComment!s(ld);
	}
}
