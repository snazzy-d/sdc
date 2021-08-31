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
	
	// Skip comments by default.
	bool tokenizeComments = false;
	
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
		uint prefixLength = s.length;
		auto ibegin = index - prefixLength;
		auto begin = base.getWithOffset(ibegin);
		
		uint iend = popComment!s();
		
		t.location = Location(begin, base.getWithOffset(iend));
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
		auto ibegin = index - prefixLength;
		auto begin = base.getWithOffset(ibegin);
		
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
		
		t.location = Location(begin, base.getWithOffset(index));
		t.name = context.getName(content[ibegin .. index]);
		
		return t;
	}
	
	Token lexString(string s)() in {
		assert(index >= s.length);
	} do {
		Token t;
		auto ibegin = index - cast(uint) s.length;
		auto begin = base.getWithOffset(ibegin);
		t.type = (s == "\'")
			? TokenType.CharacterLiteral
			: TokenType.StringLiteral;
		
		enum Delimiter = s[0];
		enum DoesEscape = Delimiter != '`';
		
		auto c = frontChar;
		while (c != Delimiter) {
			if (DoesEscape && c == '\\') {
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
			popChar();
		} else {
			t.type = TokenType.Invalid;
			t.name = context.getName("Unexpected string literal termination");
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		return t;
	}
	
	auto lexNumeric(string s)() if (s.length == 1 && isDigit(s[0])) {
		return lexNumeric(s[0]);
	}
	
	Token lexNumeric(string s)() if (s.length == 2 && s[0] == '0') {
		Token t;
		t.type = TokenType.IntegerLiteral;
		auto ibegin = index - 2;
		auto begin = base.getWithOffset(ibegin);
		
		auto c = frontChar;
		switch(s[1] | 0x20) {
			case 'b':
				assert(c == '0' || c == '1', "invalid integer literal");
				while (true) {
					while (c == '0' || c == '1') {
						popChar();
						c = frontChar;
					}
					
					if (c == '_') {
						popChar();
						c = frontChar;
						continue;
					}
					
					break;
				}
				
				break;
			
			case 'x':
				auto hc = c | 0x20;
				assert((c >= '0' && c <= '9') || (hc >= 'a' && hc <= 'f'), "invalid integer literal");
				while (true) {
					hc = c | 0x20;
					while ((c >= '0' && c <= '9') || (hc >= 'a' && hc <= 'f')) {
						popChar();
						c = frontChar;
						hc = c | 0x20;
					}
					
					if (c == '_') {
						popChar();
						c = frontChar;
						continue;
					}
					
					break;
				}
				
				break;
			
			default :
				assert(0, s ~ " is not a valid prefix.");
		}
		
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
			
			default:
				break;
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		return t;
	}
	
	auto lexNumeric(char c) {
		Token t;
		t.type = TokenType.IntegerLiteral;
		auto ibegin = index - 1;
		auto begin = base.getWithOffset(ibegin);
		
		assert(c >= '0' && c <= '9', "invalid integer literal");
		
		c = frontChar;
		while (true) {
			while (c >= '0' && c <= '9') {
				popChar();
				c = frontChar;
			}
			
			if (c == '_') {
				popChar();
				c = frontChar;
				continue;
			}
			
			break;
		}
		
		switch (c) {
			case '.':
				auto lookAhead = content;
				lookAhead.popFront();
				
				if (lookAhead.front.isDigit()) {
					popChar();
					
					t.type = TokenType.FloatLiteral;
					
					assert(0, "No floating point ATM");
					// pumpChars!isDigit(content);
				}
				
				break;
			
			case 'U', 'u':
				popChar();
				
				c = frontChar;
				if (c == 'L' || c == 'l') {
					popChar();
				}
				
				break;
			
			case 'L', 'l':
				popChar();
				
				c = frontChar;
				if (c == 'U' || c == 'u') {
					popChar();
				}
				
				break;
			
			default:
				break;
		}
		
		t.location = Location(begin, base.getWithOffset(index));
		return t;
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
		t.location = Location(base.getWithOffset(index - l), base.getWithOffset(index));

		import source.name;
		t.name = BuiltinName!s;
		
		return t;
	}
	
	auto lexOperator(string s)() {
		enum Type = OperatorMap[s];
		
		uint l = s.length;
		
		Token t;
		t.type = Type;
		t.location = Location(base.getWithOffset(index - l), base.getWithOffset(index));

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
