module source.lexstring;

mixin template LexStringImpl(Token) {
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
