module source.lexerutil;

mixin template TokenRangeImpl(Token, alias BaseMap, alias KeywordMap, alias OperatorMap) {
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
		bool, "tokenizeComments", 1,
		bool, "_skipStrings", 1,
		uint, "__derived", 30,
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
	
	void popFront() in {
		assert(front.type != TokenType.End);
	} do {
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
			import source.lexerutil;
			// pragma(msg, typeof(this));
			// pragma(msg, lexerMixin(getLexerMap()));
			mixin(lexerMixin(getLexerMap()));
		}
		
		// Necessary because of https://issues.dlang.org/show_bug.cgi?id=22688
		assert(0);
	}
	
	void setError(ref Token t, string message) {
		t.type = TokenType.Invalid;
		t.name = context.getName(message);
	}
	
	void popChar() in {
		assert(index < content.length);
	} do {
		index++;
	}
	
	void unpopChar() in {
		assert(index > 1);
	} do {
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
			import source.lexerutil;
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

	auto lexIdentifier(string s : "" = "")() {
		uint begin = index;

		Token t;
		t.type = TokenType.Identifier;

		char c = frontChar;
		if (wantIdentifier(c) && popIdChars() > 0) {
			t.location = base.getWithOffsets(begin, index);
			t.name = context.getName(content[begin .. index]);

			return t;
		}

		// Make sure we don't stay in place.
		if (c | 0x80) {
			import std.utf;
			size_t i = index;
			content.decode(i);
			index = cast(uint) i;
		} else if (c != '\0') {
			popChar();
		}

		setError(t, "Unexpected token");
		t.location = base.getWithOffsets(begin, index);

		return t;
	}

	auto lexIdentifier(string s)() if (s != "") {
		return lexIdentifier(s.length);
	}
	
	auto lexIdentifier(uint prefixLength) in {
		assert(prefixLength > 0);
		assert(index >= prefixLength);
	} do {
		Token t;
		t.type = TokenType.Identifier;
		immutable begin = index - prefixLength;
		
		popIdChars();
		
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
	 * Integral and float literals.
	 */
	auto lexLiteralSuffix(alias Suffixes, alias CustomSuffixes = null)(uint begin) {
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
			import source.lexerutil;
			mixin(lexerMixin(getLexerMap(), "fun", ["begin", "prefixStart"]));
		}
	}
	
	template lexLiteralSuffixTpl(alias Suffixes) {
		auto fun(string s)(uint begin, uint prefixStart) {
			enum Kind = Suffixes[s];
			auto idCharCount = popIdChars();
			
			Token t;
			t.type = Kind;
			t.location = base.getWithOffsets(begin, index);
			
			if (idCharCount == 0) {
				return t;
			}
			
			// We have something else.
			setError(t, "Invalid suffix: " ~ content[prefixStart .. index]);
			return t;
		}
	}
	
	Token lexIntegralSuffix(uint begin) {
		enum IntegralSuffixMap = [
			"" : TokenType.IntegerLiteral,
			"u": TokenType.IntegerLiteral,
			"U": TokenType.IntegerLiteral,
			"ul": TokenType.IntegerLiteral,
			"uL": TokenType.IntegerLiteral,
			"Ul": TokenType.IntegerLiteral,
			"UL": TokenType.IntegerLiteral,
			"l": TokenType.IntegerLiteral,
			"L": TokenType.IntegerLiteral,
			"lu": TokenType.IntegerLiteral,
			"lU": TokenType.IntegerLiteral,
			"Lu": TokenType.IntegerLiteral,
			"LU": TokenType.IntegerLiteral,
			"f": TokenType.FloatLiteral,
			"F": TokenType.FloatLiteral,
		];
		
		return lexLiteralSuffix!IntegralSuffixMap(begin);
	}
	
	auto lexFloatSuffixError(string s : "l")(uint begin, uint prefixStart) {
		Token t;
		t.location = base.getWithOffsets(begin, index);
		setError(t, "Use 'L' suffix instead of 'l'");
		return t;
	}
	
	Token lexFloatSuffix(uint begin) {
		return lexLiteralSuffix!([
			"" : TokenType.FloatLiteral,
			"f": TokenType.FloatLiteral,
			"F": TokenType.FloatLiteral,
			"L": TokenType.FloatLiteral,
		], [
			"l": "lexFloatSuffixError",
		])(begin);
	}
	
	Token lexFloatLiteral(alias isFun, alias popFun, char E)(uint begin) {
		popFun();
		
		bool isFloat = false;
		if (frontChar == '.') {
			auto savePoint = index;
			
			popChar();
			if (frontChar == '.') {
				index = savePoint;
				goto LexSuffix;
			}
			
			auto floatSavePoint = index;

			popSkippableChars();
			
			if (wantIdentifier(frontChar)) {
				index = savePoint;
				goto LexSuffix;
			}
			
			index = floatSavePoint;
			isFloat = true;
			
			if (isFun(frontChar)) {
				popChar();
				popFun();
			}
		}
		
		if ((frontChar | 0x20) == E) {
			isFloat = true;
			popChar();
			
			auto c = frontChar;
			if (c == '+' || c == '-') {
				popChar();
			}
			
			popFun();
		}
		
	LexSuffix:
		return isFloat ? lexFloatSuffix(begin) : lexIntegralSuffix(begin);
	}
	
	/**
	 * Binary literals.
	 */
	static bool isBinary(char c) {
		return c == '0' || c == '1';
	}
	
	void popBinary() {
		auto c = frontChar;
		while (isBinary(c) || c == '_') {
			popChar();
			c = frontChar;
		}
	}
	
	Token lexNumeric(string s : "0B")() {
		return lexNumeric!"0b"();
	}
	
	Token lexNumeric(string s : "0b")() {
		uint begin = index - 2;

		while (frontChar == '_') {
			popChar();
		}

		if (isBinary(frontChar)) {
			popBinary();
			return lexIntegralSuffix(begin);
		}

		Token t;
		t.location = base.getWithOffsets(begin, index);
		setError(t, "Invalid binary sequence");

		return t;
	}
	
	/**
	 * Hexadecimal literals.
	 */
	static bool isHexadecimal(char c) {
		auto hc = c | 0x20;
		return (c >= '0' && c <= '9') || (hc >= 'a' && hc <= 'f');
	}
	
	void popHexadecimal() {
		auto c = frontChar;
		while (isHexadecimal(c) || c == '_') {
			popChar();
			c = frontChar;
		}
	}
	
	Token lexNumeric(string s : "0X")() {
		return lexNumeric!"0x"();
	}
	
	Token lexNumeric(string s : "0x")() {
		uint begin = index - 2;

		while (frontChar == '_') {
			popChar();
		}

		if (isHexadecimal(frontChar)) {
			return lexFloatLiteral!(isHexadecimal, popHexadecimal, 'p')(begin);
		}

		Token t;
		t.location = base.getWithOffsets(begin, index);
		setError(t, "Invalid hexadecimal sequence");
		return t;
	}
	
	/**
	 * Decimal literals.
	 */
	static bool isDecimal(char c) {
		return c >= '0' && c <= '9';
	}
	
	void popDecimal() {
		auto c = frontChar;
		while (isDecimal(c) || c == '_') {
			popChar();
			c = frontChar;
		}
	}
	
	auto lexNumeric(string s)() if (s.length == 1 && isDecimal(s[0])) {
		return lexNumeric(s[0]);
	}
	
	auto lexNumeric(char c) in {
		assert(isDecimal(c));
	} do {
		return lexFloatLiteral!(isDecimal, popDecimal, 'e')(index - 1);
	}
	
	/**
	 * Comments.
	 */
	uint popComment(string s)() {
		auto c = frontChar;
		
		static if (s == "//") {
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
		} else static if (s == "/*") {
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
		} else static if (s == "/+") {
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
					case '+' :
						if (c == '/') {
							popChar();
							if (!stack) {
								return index;
							}
							
							c = frontChar;
							stack--;
						}
						
						break;
					
					case '/' :
						if (c == '+') {
							popChar();
							c = frontChar;
							
							stack++;
						}
						
						break;
					
					default :
						assert(0, "Unreachable.");
				}
			}
		} else {
			static assert(0, s ~ " isn't a known type of comment.");
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

	/**
	 * String literals.
	 */
	bool lexEscapeSequence(ref string decoded) {
		char c = frontChar;
		
		switch (c) {
			case '\'', '"', '\\':
				// Noop.
				break;
			
			case '?':
				assert(0, "WTF is \\?");
			
			case '0':
				c = '\0';
				break;
			
			case 'a':
				c = '\a';
				break;
			
			case 'b':
				c = '\b';
				break;
			
			case 'f':
				c = '\f';
				break;
			
			case 'r':
				c = '\r';
				break;
			
			case 'n':
				c = '\n';
				break;
			
			case 't':
				c = '\t';
				break;
			
			case 'v':
				c = '\v';
				break;
			
			case 'u', 'U':
				popChar();
				
				uint v = 0;
				
				auto length = 4 * (c == 'U') + 4;
				foreach (i; 0 .. length) {
					c = frontChar;
					
					uint d = c - '0';
					uint h = ((c | 0x20) - 'a') & 0xff;
					uint n = (d < 10) ? d : (h + 10);
					
					if (n >= 16) {
						return false;
					}
					
					v |= n << (4 * (length - i - 1));
					popChar();
				}
				
				char[4] buf;
				
				import std.utf;
				auto i = encode(buf, v);
				
				decoded ~= buf[0 .. i];
				return true;
			
			case '&':
				assert(0, "HTML5 named character references not implemented");
			
			default:
				return false;
		}
		
		popChar();
		decoded ~= c;
		return true;
	}
	
	Token lexRawString(char Delimiter = '`')(uint begin) {
		Token t;
		t.type = TokenType.StringLiteral;
		
		size_t start = index;
		
		auto c = frontChar;
		while (c != Delimiter && c != '\0') {
			popChar();
			c = frontChar;
		}

		if (c == '\0') {
			setError(t, "Unexpected end of file");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}
		
		if (decodeStrings) {
			string decoded = content[start .. index];
			t.name = context.getName(decoded);
		}
		
		popChar();
		
		t.location = base.getWithOffsets(begin, index);
		return t;
	}
	
	Token lexString(string s : "`")() {
		immutable begin = cast(uint) (index - s.length);
		return lexRawString!'`'(begin);
	}

	Token lexString(string s : "'")() {
		immutable begin = cast(uint) (index - s.length);
		return lexRawString!'\''(begin);
	}

	Token lexDecodedString(char Delimiter = '"', TokenType TT = TokenType.StringLiteral)(uint begin) {
		Token t;
		t.type = TT;
		
		size_t start = index;
		string decoded;
		
		auto c = frontChar;
		while (c != Delimiter && c != '\0') {
			if (c == '\\') {
				immutable beginEscape = index;
				
				if (decodeStrings) {
					scope(success) {
						start = index;
					}
					
					// Workaround for https://issues.dlang.org/show_bug.cgi?id=22271
					if (decoded == "") {
						decoded = content[start .. index];
					} else {
						decoded ~= content[start .. index];
					}
					
					popChar();
					if (!lexEscapeSequence(decoded)) {
						t.location = base.getWithOffsets(beginEscape, index);
						setError(t, "Invalid escape sequence");
						return t;
					}
					
					c = frontChar;
					continue;
				}
				
				popChar();
				c = frontChar;
			}
			
			popChar();
			c = frontChar;
		}
		
		if (c == '\0') {
			setError(t, "Unexpected end of file");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}
		
		if (decodeStrings) {
			// Workaround for https://issues.dlang.org/show_bug.cgi?id=22271
			if (decoded == "") {
				decoded = content[start .. index];
			} else {
				decoded ~= content[start .. index];
			}
			
			t.name = context.getName(decoded);
		}
		
		popChar();
		
		t.location = base.getWithOffsets(begin, index);
		return t;
	}
	
	Token lexString(string s : `"`)() {
		immutable begin = cast(uint) (index - s.length);
		return lexDecodedString!'"'(begin);
	}

	Token lexCharacter(string s : `'`)() {
		immutable begin = cast(uint) (index - s.length);
		return lexDecodedString!('\'', TokenType.CharacterLiteral)(begin);
	}
}

@property
char front(string s) {
	return s[0];
}

void popFront(ref string s) {
	s = s[1 .. $];
}

string lexerMixin(string[string] ids, string def = "lexIdentifier", string[] rtArgs = []) {
	return lexerMixin(ids, def, rtArgs, "");
}

private:

auto stringify(string s) {
	import std.array;
	return "`" ~ s.replace("`", "` ~ \"`\" ~ `").replace("\0", "` ~ \"\\0\" ~ `") ~ "`";
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

string lexerMixin(string[string] ids, string def, string[] rtArgs, string base) {
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
		switch(c) {
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
