module source.lexbase;

mixin template LexBaseUtils() {
private:
	uint popChar(uint count = 1) in(index + count <= content.length) {
		auto ret = index;
		index += count;
		return ret;
	}

	uint unpopChar(uint count = 1) in(index >= count) {
		auto ret = index;
		index -= count;
		return ret;
	}

	@property
	char frontChar() const in(index < content.length) {
		return content.ptr[index];
	}

	@property
	char nextChar() const in(frontChar != '\0') {
		return content.ptr[index + 1];
	}

	@property
	string remainingContent() in(index < content.length) {
		return content.ptr[index .. content.length];
	}

	auto skip(string s)() {
		// Just skip over whitespaces.
	}

public:
	bool reachedEOF() const {
		return index + 1 >= content.length;
	}
}

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
		auto r = this;
		r.tokenizeComments = wc;
		return r;
	}

	@property
	bool decodeLiterals() const {
		return !_skipLiterals;
	}

	auto withLiteralDecoding(bool ld = true) {
		auto r = this;
		r._skipLiterals = !ld;
		return r;
	}

	@property
	bool preprocessDirectives() const {
		return !_skipPreprocessorDirectives;
	}

	auto withPreprocessorDirectives(bool ppd = true) {
		auto r = this;
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
		previous = fr.previous;
	}

	@property
	bool empty() const {
		return t.type == TokenType.End;
	}

	/**
	 * Basic utilities.
	 */
	mixin LexBaseUtils;

private:
	/**
	 * White spaces.
	 */
	import source.lexwhitespace;
	mixin LexWhiteSpaceImpl;

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

	auto getExpectedError(alias failWithError = getError)(
		uint begin,
		string expected,
		bool consume = false,
	) {
		import std.format;
		auto found =
			base.isMixin() ? "the end of the input" : "the end of the file";

		if (!reachedEOF()) {
			auto start = index;
			dchar[1] c;

			import source.util.utf8;
			if (!decode(content, index, c[0])) {
				return failWithError(start, "Invalid UTF-8 sequence.");
			}

			found = format!"%(%s%)"(c);
			if (!consume) {
				index = start;
			}
		}

		return failWithError(begin,
		                     format!"Expected %s, not %s."(expected, found));
	}

	/**
	 * Fallback for invalid prefixes.
	 */
	auto lexDefaultFallback(string s)() {
		if (s == "") {
			return lexIdentifier();
		}

		import source.util.identifier;
		enum PL = skipIdentifier(s ~ '\0');
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
	auto popIdentifier() {
		import source.util.identifier;
		auto count = skipIdentifier(remainingContent);

		popChar(count);
		return count;
	}

	auto popIdentifierContinuation() {
		uint begin = index;

		import source.util.identifier;
		index = skipIdContinue(content, index);

		return index - begin;
	}

	auto popIdentifierWithPrefix(string s)() {
		return (s == "") ? popIdentifier() : popIdentifierContinuation();
	}

	auto lexIdentifier(string s = "")() {
		import source.util.identifier;
		static assert(skipIdentifier(s ~ '\0') == s.length,
		              s ~ " must be an identifier.");

		uint l = s.length;
		uint begin = index - l;

		if (popIdentifierWithPrefix!s() == 0 && s == "") {
			return lexInvalid();
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

		if (popIdentifierWithPrefix!s() == 0) {
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
	template lexLiteralSuffix(alias Suffixes, A...) {
		Token lexLiteralSuffix(T...)(uint begin, T args) {
			const prefixStart = index;

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

		private
		Token fun(string s, T...)(uint begin, uint prefixStart, T args) {
			if (popIdentifierContinuation() > 0) {
				// We have something else.
				import std.format;
				return getError(
					prefixStart,
					format!"`%s` is not a valid suffix."(
						content[prefixStart .. index]),
				);
			}

			auto location = base.getWithOffsets(begin, index);

			import std.format;
			return mixin(format!"%s!(s, A)(location, args)"(Suffixes[s]));
		}
	}

	/**
	 * Comments.
	 */
	Token getComment(string s)(uint begin, uint end) {
		auto location = base.getWithOffsets(begin, end);
		return Token.getComment!s(location);
	}

	Token lexComment(string s)() if (s == "#" || s == "//") {
		uint l = s.length;
		uint begin = index - l;

		return getComment!s(begin, popLine());
	}

	Token lexComment(string s : "/*")() {
		uint l = s.length;
		uint begin = index - l;

		uint state = 0;
		uint pstate = 0;

		import source.swar.comment;
		while (remainingContent.length > 8
			       && canSkipOverComment!8(remainingContent, state)) {
			pstate = state;
			popChar(8);
		}

		auto c = frontChar;
		auto pc = getPreviousCharFromState(pstate);

		while (pc != '*' || c != '/') {
			if (reachedEOF()) {
				return getError(begin, "Comment must end with `*/`.");
			}

			popChar();
			pc = c;
			c = frontChar;
		}

		popChar();
		return getComment!s(begin, index);
	}

	Token lexComment(string s : "/+")() {
		uint l = s.length;
		uint begin = index - l;

		uint stack = 0;
		while (true) {
			uint state1 = 0, state2 = 0;
			uint pstate1 = 0, pstate2 = 0;

			import source.swar.comment;
			while (remainingContent.length > 8
				       && canSkipOverNestedComment!8(remainingContent, state1,
				                                     state2)) {
				pstate1 = state1;
				pstate2 = state2;
				popChar(8);
			}

			auto c = frontChar;
			auto pc = getPreviousCharFromNestedState(pstate1, pstate2);

			while ((pc != '+' || c != '/') && (pc != '/' || c != '+')) {
				if (reachedEOF()) {
					return getError(begin, "Comment must end with `+/`.");
				}

				popChar();
				pc = c;
				c = frontChar;
			}

			popChar();
			if (c == '+') {
				stack++;
				continue;
			}

			assert(c == '/');
			if (stack > 0) {
				stack--;
				continue;
			}

			return getComment!s(begin, index);
		}
	}

	bool skipComment(string s)(Token c) {
		return c.type == TokenType.Comment && !tokenizeComments;
	}
}

unittest {
	import source.context, source.dlexer;
	auto context = new Context();

	auto makeTestLexer(string s) {
		import source.location;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		return lex(base, context);
	}

	auto checkLexComment(string s, string expected) {
		auto lex = makeTestLexer(s).withComments(true);

		import source.parserutil;
		lex.match(TokenType.Begin);

		auto t = lex.match(TokenType.Comment);
		assert(t.toString(context) == expected);

		assert(lex.front.type == TokenType.End);
		assert(lex.index == s.length + 1);
	}

	auto checkLexInvalid(string s, string error) {
		auto lex = makeTestLexer(s);

		import source.parserutil;
		lex.match(TokenType.Begin);

		auto t = lex.match(TokenType.Invalid);
		assert(t.error.toString(context) == error);
	}

	checkLexComment("//", "//");
	checkLexComment("  //", "//");
	checkLexComment("//  ", "//  ");
	checkLexComment("// foo\n", "// foo");
	checkLexComment("// foo\u0085", "// foo");
	checkLexComment("// foo\u2028", "// foo");
	checkLexComment("// foo\u2029", "// foo");
	checkLexComment("//\0foo\r", "//\0foo");
	checkLexComment("//\xc2foo\r\n", "//\xc2foo");
	checkLexComment("//\xc2foo\xc2\u0085", "//\xc2foo\xc2");

	checkLexComment("/**/", "/**/");
	checkLexComment("/*/*/", "/*/*/");
	checkLexComment("/*/**/", "/*/**/");
	checkLexInvalid("/*", "Comment must end with `*/`.");
	checkLexInvalid("/*/", "Comment must end with `*/`.");

	checkLexComment("/++/", "/++/");
	checkLexComment("/+/++/+/", "/+/++/+/");
	checkLexComment("/+/++/+/", "/+/++/+/");
	checkLexComment("/+/++/++/", "/+/++/++/");
	checkLexInvalid("/+", "Comment must end with `+/`.");
	checkLexInvalid("/+/", "Comment must end with `+/`.");
	checkLexInvalid("/+/+", "Comment must end with `+/`.");
	checkLexInvalid("/+/++/", "Comment must end with `+/`.");

	checkLexComment("  /**/", "/**/");
	checkLexComment("/**/  ", "/**/");
	checkLexComment("  /**/  ", "/**/");
	checkLexComment("  /++/", "/++/");
	checkLexComment("/++/  ", "/++/");
	checkLexComment("  /++/  ", "/++/");

	auto spaces = "";
	auto newlines = "";
	auto stars = "";
	auto plus = "";
	auto zeros = "";
	auto slashes = "";
	foreach (i; 0 .. 256) {
		void checkPadComment(string pad) {
			auto s = "/*" ~ pad ~ "*/";
			checkLexComment(s, s);

			s = "/+" ~ pad ~ "+/";
			checkLexComment(s, s);
		}

		spaces ~= ' ';
		checkPadComment(spaces);

		newlines ~= '\n';
		checkPadComment(newlines);

		stars ~= '*';
		checkPadComment(stars);

		plus ~= '+';
		checkPadComment(plus);

		zeros ~= '\0';
		checkPadComment(zeros);

		slashes ~= '/';
		auto s = "/*" ~ slashes ~ "*/";
		checkLexComment(s, s);
		s = "/+" ~ slashes ~ "++/+/";
		checkLexComment(s, s);

		s = "//" ~ slashes;
		checkLexComment(s, s);

		import source.lexwhitespace;
		foreach (nl; LineBreaks) {
			checkLexComment(s ~ nl, s);
		}
	}

	// Go over invalid unicode.
	checkLexInvalid("\xe2\x82", "Invalid UTF-8 sequence.");
}
