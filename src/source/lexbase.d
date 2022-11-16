module source.lexbase;

mixin template LexBaseImpl(Token, alias BaseMap, alias KeywordMap,
                           alias OperatorMap) {
	// TODO: We shouldn't let consumer play with the internal state of the lexer.
	// Instead, we should provide accessor to useful members.
	// private:
	Token t;

	import source.location;
	Position previous;
	Position base;

	uint index;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		bool, "tokenizeComments", 1,
		bool, "_skipLiterals", 1,
		bool, "_skipPreprocessorDirectives", 1,
		uint, "__derived", 29,
		// sdfmt on
	));

	import source.context;
	Context context;

	string content;

	alias TokenRange = typeof(this);
	alias TokenType = typeof(Token.init.type);

	auto withComments(bool wc = true) {
		auto r = this.save;
		r.tokenizeComments = wc;
		return r;
	}

	@property
	bool decodeLiterals() const {
		return !_skipLiterals;
	}

	auto withLiteralDecoding(bool ld = true) {
		auto r = this.save;
		r._skipLiterals = !ld;
		return r;
	}

	@property
	bool preprocessDirectives() const {
		return !_skipPreprocessorDirectives;
	}

	auto withPreprocessorDirectives(bool ppd = true) {
		auto r = this.save;
		r._skipPreprocessorDirectives = !ppd;
		return r;
	}

	/**
	 * Return a copy of this lexer that:
	 *  - skip over comments.
	 *  - do not decode strings.
	 *  - do not try to process line directives.
	 */
	auto getLookahead() {
		return withComments(false).withLiteralDecoding(false)
		                          .withPreprocessorDirectives(false);
	}

	@property
	auto front() inout {
		return t;
	}

	void popFront() in(front.type != TokenType.End) {
		previous = t.location.stop;
		t = getNextToken();

		/+
		// Exprerience the token deluge !
		if (t.type != TokenType.End) {
			import util.terminal, std.conv;
			outputCaretDiagnostics(
				t.location.getFullLocation(context),
				to!string(t.type),
			);
		}
		// +/
	}

	void moveTo(ref TokenRange fr) in {
		assert(base is fr.base);
		assert(context is fr.context);
		assert(content is fr.content);
		assert(index < fr.index);
	} do {
		index = fr.index;
		t = fr.t;
	}

	@property
	auto save() inout {
		return this;
	}

	@property
	bool empty() const {
		return t.type == TokenType.End;
	}

private:
	static getLexerMap() {
		string[string] ret;

		foreach (kw, _; KeywordMap) {
			ret[kw] = "lexKeyword";
		}

		foreach (op, _; OperatorMap) {
			ret[op] = "lexOperator";
		}

		foreach (op, fun; BaseMap) {
			ret[op] = fun;
		}

		return ret;
	}

	auto getNextToken() {
		static getMap() {
			auto ret = getLexerMap();

			foreach (op; WhiteSpaces) {
				ret[op] = "-skip";
			}

			return ret;
		}

		while (true) {
			// Fast track the usual suspects: space and tabs, and \n.
			auto c = frontChar;
			while (c == ' ' || c == '\t' || c == '\n') {
				popChar();
				c = frontChar;
			}

			import source.lexermixin;
			// pragma(msg, lexerMixin(getMap()));
			mixin(lexerMixin(getMap()));
		}

		// Necessary because of https://issues.dlang.org/show_bug.cgi?id=22688
		assert(0, "unreachable");
	}

	Token getError(Location loc, Name message) {
		return Token.getError(loc, message);
	}

	Token getError(Location loc, string message) {
		return getError(loc, context.getName(message));
	}

	Token getError(uint begin, string message) {
		return getError(base.getWithOffsets(begin, index), message);
	}

	uint popChar() in(index < content.length) {
		return index++;
	}

	uint unpopChar() in(index > 1) {
		return index--;
	}

	@property
	char frontChar() const {
		return content[index];
	}

	auto skip(string s)() {
		// Just skip over whitespace.
	}

	/**
	 * Whietspaces.
	 */
	enum HorizontalWhiteSpace = [
		// sdfmt off
		" ", "\t",
		"\v", // ??
		"\f", // ??

		// Unicode chapter 6.2, Table 6.2
		"\u00a0", // No break space.
		"\u1680", // Ogham space mark.

		// A bag of spaces of different sizes.
		"\u2000", "\u2001", "\u2002", "\u2003", "\u2004", "\u2005",
		"\u2006", "\u2007", "\u2008", "\u2009", "\u200a",

		"\u202f", // Narrow non breaking space.
		"\u205f", // Medium mathematical space.
		"\u3000", // Ideographic space.
		// sdfmt on
	];

	void popHorizontalWhiteSpaces() {
		static getMap() {
			string[string] ret;

			foreach (op; HorizontalWhiteSpace) {
				ret[op] = "-skip";
			}

			return ret;
		}

		while (true) {
			// Fast track the usual suspects: space and tabs.
			auto c = frontChar;
			while (c == ' ' || c == '\t') {
				popChar();
				c = frontChar;
			}

			import source.lexermixin;
			// pragma(msg, lexerMixin(getMap(), "skip"));
			mixin(lexerMixin(getMap(), "skip"));
		}
	}

	enum LineBreaks = [
		// sdfmt off
		"\r", "\n", "\r\n",
		"\u0085", // Next Line.
		"\u2028", // Line Separator.
		"\u2029", // Paragraph Separator.
		// sdfmt on
	];

	bool popLineBreak() {
		// Special case the end of file:
		// it counts as a line break, but we don't pop it.
		if (frontChar == '\0') {
			return true;
		}

		static bool t(string s)() {
			return true;
		}

		static bool f(string s)() {
			return false;
		}

		static getMap() {
			string[string] ret;

			foreach (op; LineBreaks) {
				ret[op] = "t";
			}

			return ret;
		}

		import source.lexermixin;
		// pragma(msg, lexerMixin(getMap(), "f"));
		mixin(lexerMixin(getMap(), "f"));
	}

	enum WhiteSpaces = HorizontalWhiteSpace ~ LineBreaks;

	void popWhiteSpaces() {
		static getMap() {
			string[string] ret;

			foreach (op; WhiteSpaces) {
				ret[op] = "-skip";
			}

			return ret;
		}

		while (true) {
			// Fast track the usual suspects: space and tabs, and \n.
			auto c = frontChar;
			while (c == ' ' || c == '\t' || c == '\n') {
				popChar();
				c = frontChar;
			}

			import source.lexermixin;
			// pragma(msg, lexerMixin(getMap(), "skip"));
			mixin(lexerMixin(getMap(), "skip"));
		}
	}

	/**
	 * Fallback for invalid prefixes.
	 */
	static identifierPrefixLength(string s) {
		if (s == "" || !wantIdentifier(s[0])) {
			return 0;
		}

		foreach (size_t i, dchar c; s) {
			import std.uni;
			if (c != '_' && !isAlphaNum(c)) {
				return i;
			}
		}

		return s.length;
	}

	auto lexDefaultFallback(string s)() {
		if (s == "") {
			return lexIdentifier();
		}

		enum PL = identifierPrefixLength(s);
		enum Delta = s.length - PL;
		index -= Delta;

		static if (PL == 0) {
			return lexInvalid();
		} else {
			enum PS = s[0 .. PL];
			return lexIdentifier!PS();
		}
	}

	auto lexInvalid() {
		uint begin = index;
		char c = frontChar;

		// Make sure we don't stay in place.
		if (c < 0x80) {
			if (c != '\0') {
				popChar();
			}
		} else {
			dchar d;

			import source.util.utf8;
			if (!decode(content, index, d)) {
				return getError(begin, "Invalid UTF-8 sequence.");
			}
		}

		return getError(begin, "Unexpected token.");
	}

	/**
	 * Identifiers.
	 */
	static wantIdentifier(char c) {
		auto hc = c | 0x20;
		return c == '_' || (c & 0x80) || (hc >= 'a' && hc <= 'z');
	}

	auto popIdChars() {
		const begin = index;
		while (true) {
			char c = frontChar;

			import std.ascii : isAlphaNum;
			while (c == '_' || isAlphaNum(c)) {
				popChar();
				c = frontChar;
			}

			if (c < 0x80) {
				break;
			}

			uint i = index;
			dchar u;

			import source.util.utf8;
			if (!decode(content, i, u)) {
				break;
			}

			import std.uni : isAlpha;
			if (!isAlpha(u)) {
				break;
			}

			index = i;
		}

		return begin - index;
	}

	auto lexIdentifier(string s = "")() {
		static assert(identifierPrefixLength(s) == s.length,
		              s ~ " must be an identifier.");

		uint l = s.length;
		uint begin = index - l;

		if (s == "") {
			if (!wantIdentifier(frontChar) || popIdChars() == 0) {
				return lexInvalid();
			}
		} else {
			popIdChars();
		}

		auto location = base.getWithOffsets(begin, index);
		return Token
			.getIdentifier(location, context.getName(content[begin .. index]));
	}

	/**
	 * Operators.
	 */
	auto lexOperator(string s)() {
		uint l = s.length;
		uint begin = index - l;
		auto loc = base.getWithOffsets(begin, index);
		return Token.getOperator!s(loc);
	}

	/**
	 * Keywords.
	 */
	import source.name;
	auto lexKeyword(string s)() {
		enum Type = KeywordMap[s];
		uint l = s.length;
		uint begin = index - l;

		auto location = base.getWithOffsets(begin, index);

		if (popIdChars() == 0) {
			return Token.getKeyword!s(location);
		}

		// This is an identifier that happened to start
		// like a keyword.
		return Token
			.getIdentifier(location, context.getName(content[begin .. index]));
	}

	/**
	 * Utilities to handle literals suffixes.
	 */
	Token lexLiteralSuffix(alias Suffixes, T...)(uint begin, T args) {
		const prefixStart = index;
		alias fun = lexLiteralSuffixTpl!Suffixes.fun;

		static getLexerMap() {
			string[string] ret;

			foreach (op, _; Suffixes) {
				ret[op] = "fun";
			}

			return ret;
		}

		while (true) {
			import source.lexermixin;
			mixin(lexerMixin(getLexerMap(), "fun",
			                 ["begin", "prefixStart", "args"]));
		}
	}

	template lexLiteralSuffixTpl(alias Suffixes) {
		Token fun(string s, T...)(uint begin, uint prefixStart, T args) {
			if (popIdChars() != 0) {
				// We have something else.
				import std.format;
				return getError(
					prefixStart,
					format!"Invalid suffix: `%s`."(
						content[prefixStart .. index]),
				);
			}

			auto location = base.getWithOffsets(begin, index);

			import std.format;
			return mixin(format!"%s!s(location, args)"(Suffixes[s]));
		}
	}

	/**
	 * Comments.
	 */
	Token getComment(string s)(uint begin, uint end) {
		auto location = base.getWithOffsets(begin, end);
		return Token.getComment!s(location);
	}

	uint lexLine() {
		auto c = frontChar;

		// TODO: check for unicode line break.
		while (c != '\0' && c != '\n' && c != '\r') {
			popChar();
			c = frontChar;
		}

		uint end = index;
		if (c == '\0') {
			// The end of the file is also the end of the line
			// so no error is needed in this case.
			return end;
		}

		popChar();
		if (c == '\r' && frontChar == '\n') {
			popChar();
		}

		return end;
	}

	Token lexComment(string s)() if (s == "#" || s == "//") {
		uint l = s.length;
		uint begin = index - l;

		return getComment!s(begin, lexLine());
	}

	Token lexComment(string s : "/*")() {
		uint l = s.length;
		uint begin = index - l;

		auto c = frontChar;

		char pc = '\0';
		while (c != '\0' && (pc != '*' || c != '/')) {
			popChar();
			pc = c;
			c = frontChar;
		}

		if (c == '\0') {
			return getError(begin, "Unexpected end of file.");
		}

		popChar();
		return getComment!s(begin, index);
	}

	Token lexComment(string s : "/+")() {
		uint l = s.length;
		uint begin = index - l;

		auto c = frontChar;

		uint stack = 0;
		while (true) {
			char pc = '\0';
			while (c != '\0' && c != '/') {
				popChar();
				pc = c;
				c = frontChar;
			}

			if (c == '\0') {
				return getError(begin, "Unexpected end of file.");
			}

			popChar();
			scope(success) {
				c = frontChar;
			}

			if (pc == '+') {
				if (!stack) {
					return getComment!s(begin, index);
				}

				stack--;
				continue;
			}

			// We have a nested /+ comment.
			if (frontChar == '+') {
				stack++;
				popChar();
			}
		}
	}

	bool skipComment(string s)(Token c) {
		return c.type == TokenType.Comment && !tokenizeComments;
	}
}
