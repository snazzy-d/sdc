module source.lexstring;

mixin template LexStringImpl(Token, alias StringSuffixes, alias CustomStringSuffixes = null) {
	/**
	 * Character literals.
	 */
	Token lexCharacter(string s : `'`)() {
		uint l = s.length;
		auto t = lexDecodedString!('\'')(index - l);
		if (t.type != TokenType.Invalid) {
			t.type = TokenType.CharacterLiteral;
		}
		
		return t;
	}
	
	/**
	 * String literals.
	 */
	auto lexStrignSuffix(uint begin) {
		return lexLiteralSuffix!(StringSuffixes, CustomStringSuffixes)(begin);
	}
	
	Token buildRawString(uint begin, size_t start, size_t stop) {
		auto t = lexStrignSuffix(begin);
		if (t.type == TokenType.Invalid) {
			// Bubble up errors.
			return t;
		}

		if (decodeStrings) {
			t.name = context.getName(content[start .. stop]);
		}

		return t;
	}
	
	Token lexRawString(char Delimiter = '`')(uint begin) {
		size_t start = index;
		
		auto c = frontChar;
		while (c != Delimiter && c != '\0') {
			popChar();
			c = frontChar;
		}

		if (c == '\0') {
			Token t;
			setError(t, "Unexpected end of file");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}
		
		uint end = index;
		popChar();
		
		return buildRawString(begin, start, end);
	}
	
	Token lexString(string s : "`")() {
		uint l = s.length;
		return lexRawString!'`'(index - l);
	}

	Token lexString(string s : "'")() {
		uint l = s.length;
		return lexRawString!'\''(index - l);
	}

	Token lexDecodedString(char Delimiter = '"')(uint begin) {
		size_t start = index;
		string decoded;
		
		auto c = frontChar;
		while (c != Delimiter && c != '\0') {
			if (c != '\\') {
				popChar();
				c = frontChar;
				continue;
			}
			
			if (!decodeStrings) {
				popChar();
				
				c = frontChar;
				if (c == '\0') {
					break;
				}
				
				popChar();
				c = frontChar;
				continue;
			}
			
			const beginEscape = index;
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
				Token t;
				setError(t, "Invalid escape sequence");
				t.location = base.getWithOffsets(beginEscape, index);
				return t;
			}
			
			c = frontChar;
		}
		
		if (c == '\0') {
			Token t;
			setError(t, "Unexpected end of file");
			t.location = base.getWithOffsets(begin, index);
			return t;
		}
		
		uint end = index;
		popChar();
		
		auto t = lexStrignSuffix(begin);
		if (t.type == TokenType.Invalid) {
			// Propagate errors.
			return t;
		}
		
		if (decodeStrings) {
			// Workaround for https://issues.dlang.org/show_bug.cgi?id=22271
			if (decoded == "") {
				decoded = content[start .. end];
			} else {
				decoded ~= content[start .. end];
			}
			
			t.name = context.getName(decoded);
		}
		
		return t;
	}
	
	Token lexString(string s : `"`)() {
		uint l = s.length;
		return lexDecodedString!'"'(index - l);
	}

	/**
	 * Escape sequences.
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
}
