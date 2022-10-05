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
		uint, "__derived", 30,
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

	/**
	 * Return a copy of this lexer that:
	 *  - skip over comments.
	 *  - do not decode strings.
	 */
	auto getLookahead() {
		return withStringDecoding(false).withComments(false);
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
	enum Skippable = [" ", "\t", "\v", "\f", "\n", "\r", "\u2028", "\u2029"];

	auto getNextToken() {
		static getLexerMap() {
			auto ret = BaseMap;

			foreach (op; Skippable) {
				ret[op] = "-skip";
			}

			foreach (kw, _; KeywordMap) {
				ret[kw] = "lexKeyword";
			}

			foreach (op, _; OperatorMap) {
				ret[op] = "lexOperator";
			}

			return ret;
		}

		while (true) {
			import source.lexbase;
			// pragma(msg, typeof(this));
			// pragma(msg, lexerMixin(getLexerMap()));
			mixin(lexerMixin(getLexerMap()));
		}

		// Necessary because of https://issues.dlang.org/show_bug.cgi?id=22688
		assert(0);
	}

	Token getError(uint begin, string message) {
		Token t;
		t.type = TokenType.Invalid;
		t.name = context.getName(message);
		t.location = base.getWithOffsets(begin, index);
		return t;
	}

	void popChar() in(index < content.length) {
		index++;
	}

	void unpopChar() in(index > 1) {
		index--;
	}

	void popSkippableChars() {
		static getLexerMap() {
			string[string] ret;

			foreach (op; Skippable) {
				ret[op] = "-skip";
			}

			return ret;
		}

		while (true) {
			import source.lexbase;
			// pragma(msg, typeof(this));
			// pragma(msg, lexerMixin(getLexerMap(), "__noop"));
			mixin(lexerMixin(getLexerMap(), "skip"));
		}
	}

	@property
	char frontChar() const {
		return content[index];
	}

	auto skip(string s)() {
		// Just skip over whitespace.
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
		enum Type = OperatorMap[s];
		uint l = s.length;

		Token t;
		t.type = Type;
		t.location = base.getWithOffsets(index - l, index);
		t.name = BuiltinName!s;

		return t;
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
	uint popComment(string s : "#")() {
		auto c = frontChar;

		// TODO: check for unicode line break.
		while (c != '\n' && c != '\r') {
			if (c == 0) {
				return index;
			}

			popChar();
			c = frontChar;
		}

		uint ret = index;

		popChar();
		if (c == '\r') {
			if (frontChar == '\n') {
				popChar();
			}
		}

		return ret;
	}

	uint popComment(string s : "//")() {
		return popComment!"#"();
	}

	uint popComment(string s : "/*")() {
		auto c = frontChar;

		while (true) {
			while (c != '*') {
				popChar();
				c = frontChar;
			}

			auto match = c;
			popChar();
			c = frontChar;

			if (c == '/') {
				popChar();
				return index;
			}
		}
	}

	uint popComment(string s : "/+")() {
		auto c = frontChar;

		uint stack = 0;
		while (true) {
			while (c != '+' && c != '/') {
				popChar();
				c = frontChar;
			}

			auto match = c;
			popChar();
			c = frontChar;

			switch (match) {
				case '+':
					if (c == '/') {
						popChar();
						if (!stack) {
							return index;
						}

						c = frontChar;
						stack--;
					}

					break;

				case '/':
					if (c == '+') {
						popChar();
						c = frontChar;

						stack++;
					}

					break;

				default:
					assert(0, "Unreachable.");
			}
		}
	}

	auto lexComment(string s)() {
		Token t;
		t.type = TokenType.Comment;

		uint begin = index - uint(s.length);
		uint end = popComment!s();

		t.location = base.getWithOffsets(begin, end);
		return t;
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

auto stringify(string s) {
	import std.array;
	return "`"
		~ s.replace("`", "` ~ \"`\" ~ `").replace("\0", "` ~ \"\\0\" ~ `")
		~ "`";
}

auto getLexingCode(string fun, string[] rtArgs, string base) {
	import std.array;
	auto args = "!(" ~ stringify(base) ~ ")(" ~ rtArgs.join(", ") ~ ")";

	switch (fun[0]) {
		case '-':
			return "
				" ~ fun[1 .. $] ~ args ~ ";
				continue;";

		case '?':
			size_t i = 1;
			while (fun[i] != ':') {
				i++;
			}

			size_t endcond = i;
			while (fun[i] != '|') {
				i++;
			}

			auto cond = fun[1 .. endcond];
			auto lexCmd = fun[endcond + 1 .. i];
			auto skipCmd = fun[i + 1 .. $];

			return "
				if (" ~ cond ~ ") {
					return " ~ lexCmd ~ args ~ ";
				} else {
					" ~ skipCmd ~ args ~ ";
					continue;
				}";

		default:
			return "
				return " ~ fun ~ args ~ ";";
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
		// TODO: have a real function to handle that.
		string charLit;
		switch (c) {
			case '\0':
				charLit = "\\0";
				break;

			case '\'':
				charLit = "\\'";
				break;

			case '\t':
				charLit = "\\t";
				break;

			case '\v':
				charLit = "\\v";
				break;

			case '\f':
				charLit = "\\f";
				break;

			case '\n':
				charLit = "\\n";
				break;

			case '\r':
				charLit = "\\r";
				break;

			default:
				if (c < 0x80) {
					charLit = [c];
					break;
				}

				static char toHexChar(ubyte n) {
					return ((n < 10) ? (n + '0') : (n - 10 + 'a')) & 0xff;
				}

				static string toHexString(ubyte c) {
					return [toHexChar(c >> 4), toHexChar(c & 0x0f)];
				}

				charLit = "\\x" ~ toHexString(c);
				break;
		}

		ret ~= "
			case '" ~ charLit ~ "':
				popChar();";

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
		ret ~= "
			default:" ~ getLexingCode(defaultFun, rtArgs, base) ~ "
		}
		";
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
