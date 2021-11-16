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
		bool, "skipStrings", 1,
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
	
	auto withStringDecoding(bool sd = true) {
		auto r = this.save;
		r.skipStrings = !sd;
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
	auto getNextToken() {
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
		
		while (true) {
			import source.lexerutil;
			// pragma(msg, typeof(this));
			// pragma(msg, lexerMixin(getLexerMap()));
			mixin(lexerMixin(getLexerMap()));
		}
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
	
	@property
	char frontChar() const {
		return content[index];
	}
	
	auto skip(string s)() {
		// Just skip over whitespace.
	}
	
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
	
	auto lexIdentifier(string s)() {
		static if (s == "") {
			if (isIdChar(frontChar)) {
				popChar();
				return lexIdentifier(1);
			}
			
			// XXX: proper error reporting.
			assert(frontChar & 0x80, "lex error");
			
			// XXX: Dafuq does this need to be a size_t ?
			size_t i = index;
			
			import std.utf;
			auto u = content.decode(i);
			
			import std.uni;
			assert(isAlpha(u), "lex error");
			
			auto l = cast(ubyte) (i - index);
			index += l;
			return lexIdentifier(l);
		} else {
			return lexIdentifier(s.length);
		}
	}
	
	auto lexIdentifier(uint prefixLength) in {
		assert(prefixLength > 0);
		assert(index >= prefixLength);
	} do {
		Token t;
		t.type = TokenType.Identifier;
		immutable begin = index - prefixLength;
		
		while (true) {
			while (isIdChar(frontChar)) {
				popChar();
			}
			
			if (!(frontChar | 0x80)) {
				break;
			}
			
			// XXX: Dafuq does this need to be a size_t ?
			size_t i = index;
			
			import std.utf;
			auto u = content.decode(i);
			
			import std.uni;
			if (!isAlpha(u)) {
				break;
			}
			
			index = cast(uint) i;
		}
		
		t.location = base.getWithOffsets(begin, index);
		t.name = context.getName(content[begin .. index]);
		
		return t;
	}
	
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
	
	Token lexString(string s)() in {
		assert(index >= s.length);
	} do {
		immutable begin = cast(uint) (index - s.length);
		
		Token t;
		t.type = (s == "\'")
			? TokenType.CharacterLiteral
			: TokenType.StringLiteral;
		
		enum Delimiter = s[0];
		enum DoesEscape = Delimiter != '`';
		
		size_t start = index;
		string decoded;
		
		auto c = frontChar;
		while (c != Delimiter) {
			if (DoesEscape && c == '\\') {
				immutable beginEscape = index;
				
				if (!skipStrings) {
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
			
			if (c == '\0') {
				break;
			}
			
			popChar();
			c = frontChar;
		}
		
		if (c == Delimiter) {
			if (!skipStrings) {
				// Workaround for https://issues.dlang.org/show_bug.cgi?id=22271
				if (DoesEscape && decoded != "") {
					decoded ~= content[start .. index];
				} else {
					decoded = content[start .. index];
				}
				
				t.name = context.getName(decoded);
			}
			
			popChar();
		} else {
			setError(t, "Unexpected string literal termination");
		}
		
		t.location = base.getWithOffsets(begin, index);
		return t;
	}
	
	/**
	 * General integer lexing utilities.
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
	
	Token lexIntegralSuffix(uint begin) {
		Token t;
		t.type = TokenType.IntegerLiteral;
		
		auto c = frontChar;
		switch(c | 0x20) {
			case 'u':
				popChar();
				
				c = frontChar;
				if (c == 'L' || c == 'l') {
					popChar();
				}
				
				break;
			
			case 'l':
				popChar();
				
				c = frontChar;
				if (c == 'U' || c == 'u') {
					popChar();
				}
				
				break;
			
			case 'f':
				popChar();
				
				t.type = TokenType.FloatLiteral;
				break;
			
			default:
				break;
		}
		
		t.location = base.getWithOffsets(begin, index);
		return t;
	}
	
	/**
	 * Binary literals.
	 */
	Token lexNumeric(string s : "0B")() {
		return lexNumeric!"0b"();
	}
	
	Token lexNumeric(string s : "0b")() {
		if (!isBinary(frontChar)) {
			// FIXME: Proper error reporting.
			assert(0, "invalid integer literal");
		}
		
		uint begin = index - 2;
		popBinary();
		
		return lexIntegralSuffix(begin);
	}
	
	/**
	 * Hexadecimal literals.
	 */
	Token lexNumeric(string s : "0X")() {
		return lexNumeric!"0x"();
	}
	
	Token lexNumeric(string s : "0x")() {
		if (!isHexadecimal(frontChar)) {
			// FIXME: Proper error reporting.
			assert(0, "invalid integer literal");
		}
		
		uint begin = index - 2;
		popHexadecimal();
		
		auto c = frontChar;
		if ((c | 0x20) == 'p') {
			popChar();
			
			c = frontChar;
			if (c == '+' || c == '-') {
				popChar();
				c = frontChar;
			}
			
			popHexadecimal();
			
			Token t;
			t.type = TokenType.FloatLiteral;
			t.location = base.getWithOffsets(begin, index);
			return t;
		}
		
		assert(c != '.', "No floating point ATM");
		return lexIntegralSuffix(begin);
	}
	
	/**
	 * Decimal literals.
	 */
	auto lexNumeric(string s)() if (s.length == 1 && isDigit(s[0])) {
		return lexNumeric(s[0]);
	}
	
	auto lexNumeric(char c) {
		if (!isDecimal(c)) {
			// FIXME: Proper error reporting.
			assert(0, "invalid integer literal");
		}
		
		uint begin = index - 1;
		popDecimal();
		
		c = frontChar;
		if ((c | 0x20) == 'e') {
			popChar();
			
			c = frontChar;
			if (c == '+' || c == '-') {
				popChar();
				c = frontChar;
			}
			
			popDecimal();
			
			Token t;
			t.type = TokenType.FloatLiteral;
			t.location = base.getWithOffsets(begin, index);
			return t;
		}
		
		assert(c != '.', "No floating point ATM");
		return lexIntegralSuffix(begin);
	}
	
	auto lexKeyword(string s)() {
		auto c = frontChar;
		if (isIdChar(c)) {
			popChar();
			return lexIdentifier(s.length + 1);
		}
		
		if (c & 0x80) {
			size_t i = index;
			
			import std.utf;
			auto u = content.decode(i);
			
			import std.uni;
			if (isAlpha(u)) {
				auto l = cast(ubyte) (i - index);
				index += l;
				return lexIdentifier(s.length + l);
			}
		}
		
		enum Type = KeywordMap[s];
		
		uint l = s.length;
		
		Token t;
		t.type = Type;
		t.location = base.getWithOffsets(index - l, index);

		import source.name;
		t.name = BuiltinName!s;
		
		return t;
	}
	
	auto lexOperator(string s)() {
		enum Type = OperatorMap[s];
		
		uint l = s.length;
		
		Token t;
		t.type = Type;
		t.location = base.getWithOffsets(index - l, index);

		import source.name;
		t.name = BuiltinName!s;
		
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

auto isIdChar(char c) {
	import std.ascii;
	return c == '_' || isAlphaNum(c);
}

auto isDigit(char c) {
	import std.ascii;
	return std.ascii.isDigit(c);
}

string lexerMixin(string[string] ids) {
	return lexerMixin("", "lexIdentifier", ids);
}

private:

auto stringify(string s) {
	import std.array;
	return "`" ~ s.replace("`", "` ~ \"`\" ~ `").replace("\0", "` ~ \"\\0\" ~ `") ~ "`";
}

auto getLexingCode(string fun, string base) {
	auto args = "!(" ~ stringify(base) ~ ")()";
	
	switch (fun[0]) {
		case '-':
			return "
				" ~ fun[1 .. $] ~ args ~ ";
				continue;";
			
		case '!':
			size_t i = 1;
			while (fun[i] != '?') {
				i++;
			}
			
			size_t endcond = i;
			while (fun[i] != ':') {
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

string lexerMixin(string base, string def, string[string] ids) {
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
			
			case '\n':
				charLit = "\\n";
				break;
			
			case '\r':
				charLit = "\\r";
				break;
			
			default:
				charLit = [c];
		}
		
		ret ~= "
			case '" ~ charLit ~ "' :
				popChar();";
		
		auto newBase = base ~ c;
		if (subids.length == 1) {
			if (auto cdef = "" in subids) {
				ret ~= getLexingCode(*cdef, newBase);
				continue;
			}
		}
		
		ret ~= lexerMixin(newBase, def, nextLevel[c]);
	}
	
	ret ~= "
			default :" ~ getLexingCode(defaultFun, base) ~ "
		}
		";
	
	return ret;
}
