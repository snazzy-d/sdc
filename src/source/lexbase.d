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
		bool, "_skipStrings", 1,
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
	bool decodeStrings() const {
		return !_skipStrings;
	}

	auto withStringDecoding(bool sd = true) {
		auto r = this.save;
		r._skipStrings = !sd;
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
		return withComments(false).withStringDecoding(false)
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
		auto ret = BaseMap;

		foreach (kw, _; KeywordMap) {
			ret[kw] = "lexKeyword";
		}

		foreach (op, _; OperatorMap) {
			ret[op] = "lexOperator";
		}

		return ret;
	}

	auto getNextToken() {
		while (true) {
			// NB: I'm not sure if it is best to generate one giant switch
			// or if we are better off skipping whitespace and then try to
			// lex a token.
			popWhiteSpaces();

			import source.lexbase;
			// pragma(msg, lexerMixin(getLexerMap()));
			mixin(lexerMixin(getLexerMap()));
		}
	}

	Token getError(Location loc, string message) {
		Token t;
		t.type = TokenType.Invalid;
		t.name = context.getName(message);
		t.location = loc;
		return t;
	}

	Token getError(uint begin, string message) {
		return getError(base.getWithOffsets(begin, index), message);
	}

	void popChar() in(index < content.length) {
		index++;
	}

	void unpopChar() in(index > 1) {
		index--;
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

			import source.lexbase;
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

		import source.lexbase;
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

			import source.lexbase;
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
		if (c | 0x80) {
			import std.utf;
			size_t i = index;
			content.decode(i);
			index = cast(uint) i;
		} else if (c != '\0') {
			popChar();
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

			// This needs to be a size_t.
			size_t i = index;

			import std.utf;
			auto u = content.decode(i);

			import std.uni : isAlpha;
			if (!isAlpha(u)) {
				break;
			}

			index = cast(uint) i;
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

		Token t;
		t.type = TokenType.Identifier;
		t.location = base.getWithOffsets(begin, index);
		t.name = context.getName(content[begin .. index]);

		return t;
	}

	/**
	 * Operators.
	 */
	auto lexOperator(string s)() {
		uint l = s.length;
		auto loc = base.getWithOffsets(index - l, index);
		return Token.getOperator!s(loc);
	}

	/**
	 * Keywords.
	 */
	auto lexKeyword(string s)() {
		enum Type = KeywordMap[s];
		uint l = s.length;

		return lexKeyword(index - l, Type, BuiltinName!s);
	}

	import source.name;
	auto lexKeyword(uint begin, TokenType type, Name keyword) {
		auto idCharCount = popIdChars();

		Token t;
		t.type = type;
		t.name = keyword;
		t.location = base.getWithOffsets(begin, index);

		if (idCharCount == 0) {
			return t;
		}

		// This is an identifier that happened to start
		// like a keyword.
		t.type = TokenType.Identifier;
		t.name = context.getName(content[begin .. index]);

		return t;
	}

	/**
	 * Utilities to handle literals suffixes.
	 */
	auto lexLiteralSuffix(alias Suffixes,
	                      alias CustomSuffixes = null)(uint begin) {
		const prefixStart = index;
		alias fun = lexLiteralSuffixTpl!Suffixes.fun;

		static getLexerMap() {
			string[string] ret = CustomSuffixes;

			foreach (op, _; Suffixes) {
				ret[op] = "fun";
			}

			return ret;
		}

		while (true) {
			import source.lexbase;
			mixin(lexerMixin(getLexerMap(), "fun", ["begin", "prefixStart"]));
		}
	}

	template lexLiteralSuffixTpl(alias Suffixes) {
		auto fun(string s)(uint begin, uint prefixStart) {
			enum Kind = Suffixes[s];
			auto idCharCount = popIdChars();

			if (idCharCount != 0) {
				// We have something else.
				return getError(
					prefixStart,
					"Invalid suffix: " ~ content[prefixStart .. index]
				);
			}

			Token t;
			t.type = Kind;
			t.location = base.getWithOffsets(begin, index);

			return t;
		}
	}

	/**
	 * Comments.
	 */
	Token getComment(string s)(uint begin, uint end) {
		Token t;
		t.type = TokenType.Comment;
		t.name = BuiltinName!s;
		t.location = base.getWithOffsets(begin, end);
		return t;
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

@property
char front(string s) {
	return s[0];
}

void popFront(ref string s) {
	s = s[1 .. $];
}

string lexerMixin(string[string] ids, string def = "lexDefaultFallback",
                  string[] rtArgs = []) {
	return lexerMixin(ids, def, rtArgs, "");
}

private:

string toCharLit(char c) {
	switch (c) {
		case '\0':
			return "\\0";

		case '\'':
			return "\\'";

		case '"':
			return "\\\"";

		case '\\':
			return "\\\\";

		case '\a':
			return "\\a";

		case '\b':
			return "\\b";

		case '\t':
			return "\\t";

		case '\v':
			return "\\v";

		case '\f':
			return "\\f";

		case '\n':
			return "\\n";

		case '\r':
			return "\\r";

		default:
			import std.ascii;
			if (isPrintable(c)) {
				return [c];
			}

			static char toHexChar(ubyte n) {
				return ((n < 10) ? (n + '0') : (n - 10 + 'a')) & 0xff;
			}

			static string toHexString(ubyte c) {
				return [toHexChar(c >> 4), toHexChar(c & 0x0f)];
			}

			return "\\x" ~ toHexString(c);
	}
}

auto stringify(string s) {
	import std.algorithm, std.format, std.string;
	return format!`"%-(%s%)"`(s.representation.map!(c => toCharLit(c)));
}

auto getLexingCode(string fun, string[] rtArgs, string base) {
	import std.format;
	auto args = format!"(%-(%s, %))"(rtArgs);

	static getFun(string fun, string base) {
		return format!"%s!%s"(fun, stringify(base));
	}

	switch (fun[0]) {
		case '-':
			return format!"
				%s%s;
				continue;"(getFun(fun[1 .. $], base), args);

		case '?':
			return format!"
				auto t = lex%s%s;
				if (skip%1$s(t)) {
					continue;
				}

				return t;"(getFun(fun[1 .. $], base), args);

		default:
			return format!"
				return %s%s;"(getFun(fun, base), args);
	}
}

string lexerMixin(string[string] ids, string def, string[] rtArgs,
                  string base) {
	auto defaultFun = def;
	string[string][char] nextLevel;
	foreach (id, fun; ids) {
		if (id == "") {
			defaultFun = fun;
		} else {
			nextLevel[id[0]][id[1 .. $]] = fun;
		}
	}

	auto ret = "
		switch(frontChar) {";

	foreach (c, subids; nextLevel) {
		import std.format;
		ret ~= format!"
			case '%s':
				popChar();"(toCharLit(c));

		auto newBase = base ~ c;
		if (subids.length == 1) {
			if (auto cdef = "" in subids) {
				ret ~= getLexingCode(*cdef, rtArgs, newBase);
				continue;
			}
		}

		ret ~= lexerMixin(nextLevel[c], def, rtArgs, newBase);
	}

	if (base == "" || base[$ - 1] < 0x80) {
		import std.format;
		ret ~= format!"
			default:%s
		}
		"(getLexingCode(defaultFun, rtArgs, base));
	} else {
		ret ~= "
			default:
				// Do not exit in the middle of an unicode sequence.
				unpopChar();
				break;
		}

			// Fall back to the default instead.
			goto default;
			";
	}

	return ret;
}
