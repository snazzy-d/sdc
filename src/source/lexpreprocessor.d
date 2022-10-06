module source.lexpreprocessor;

mixin template LexPreprocessorImpl(Token, alias TokenHandlers,
                                   alias IdentifierHandlers) {
	void popPreprocessorWhiteSpaces() {
		popHorizontalWhiteSpaces();
	}

	Token getHashOperator(uint begin) {
		Token t;
		t.type = TokenType.Hash;
		t.location = base.getWithOffsets(begin, begin + 1);
		t.name = BuiltinName!"#";
		return t;
	}

	Token getNextPreprocessorToken() {
		while (true) {
			popPreprocessorWhiteSpaces();

			uint begin = index;

			// Generate a # operator so we don't
			// preprocess while we preprocess.
			if (frontChar == '#') {
				popChar();
				return getHashOperator(begin);
			}

			// Terminate at the end of the line.
			if (popLineBreak()) {
				Token t;
				t.type = TokenType.End;
				t.location = base.getWithOffsets(begin, index);
				t.name = BuiltinName!"\0";
				return t;
			}

			import source.lexbase;
			// pragma(msg, lexerMixin(getLexerMap()));
			mixin(lexerMixin(getLexerMap()));
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
					auto t = getComment!"#"(begin, begin);
					t.location.spanTo(lt.location.start);
					return t;

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

		auto i = getNextPreprocessorToken();
		static foreach (T, fun; TokenHandlers) {
			if (i.type == T) {
				import std.format;
				return mixin(format!"%s(begin, i)"(fun));
			}
		}

		// If this is a # alone, then we got a hash operator.
		if (i.type == TokenType.End) {
			return getHashOperator(begin);
		}

		if (i.type == TokenType.Identifier) {
			static foreach (I, fun; IdentifierHandlers) {
				if (i.name == BuiltinName!I) {
					import std.format;
					return mixin(format!"%s(begin, i)"(fun));
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
