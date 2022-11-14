module source.lexstring;

mixin template LexStringImpl(Token,
                             alias StringSuffixes = ["" : "getStringLiteral"]) {
	/**
	 * Character literals.
	 */
	Token lexCharacter(string s : `'`)() {
		uint l = s.length;
		uint begin = index - l;

		char c = frontChar;
		const start = index;
		auto dc = DecodedChar(c);

		if (c < 0x80) {
			popChar();

			if (c == '\\' && !lexEscapeSequence(dc)) {
				return getError(start, "Invalid escape sequence.");
			}
		} else {
			dchar d;

			import source.util.utf8;
			if (!decode(content, index, d)) {
				return getError(start, "Invalid UTF-8 sequence.");
			}

			dc = DecodedChar(d);
		}

		c = frontChar;
		if (c != '\'') {
			return getError(begin, "Expected `\'` to end charatcter literal.");
		}

		popChar();

		auto location = base.getWithOffsets(begin, index);
		return Token.getCharacterLiteral(location, dc);
	}

	/**
	 * String literals.
	 */
	import source.name;
	auto lexStrignSuffix(uint begin, Name value) {
		return lexLiteralSuffix!StringSuffixes(begin, value);
	}

	auto getStringLiteral(string s : "")(Location location, Name value) {
		return Token.getStringLiteral(location, value);
	}

	Token buildRawString(uint begin, size_t start, size_t stop) {
		Name value = decodeLiterals
			? context.getName(content[start .. stop])
			: BuiltinName!"";
		return lexStrignSuffix(begin, value);
	}

	Token lexRawString(char Delimiter = '`')(uint begin) {
		size_t start = index;

		auto c = frontChar;
		while (c != Delimiter && c != '\0') {
			popChar();
			c = frontChar;
		}

		if (c == '\0') {
			return getError(begin, "Unexpected end of file.");
		}

		uint end = popChar();
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

			if (!decodeLiterals) {
				popChar();

				c = frontChar;
				if (c == '\0') {
					break;
				}

				popChar();
				c = frontChar;
				continue;
			}

			scope(success) {
				start = index;
			}

			// Workaround for https://issues.dlang.org/show_bug.cgi?id=22271
			if (decoded == "") {
				decoded = content[start .. index];
			} else {
				decoded ~= content[start .. index];
			}

			const beginEscape = index;
			popChar();

			DecodedChar dc;
			if (!lexEscapeSequence(dc)) {
				return getError(beginEscape, "Invalid escape sequence.");
			}

			decoded = dc.appendTo(decoded);
			c = frontChar;
		}

		if (c == '\0') {
			return getError(begin, "Unexpected end of file.");
		}

		uint end = popChar();

		Name value;
		if (decodeLiterals) {
			// Workaround for https://issues.dlang.org/show_bug.cgi?id=22271
			if (decoded == "") {
				decoded = content[start .. end];
			} else {
				decoded ~= content[start .. end];
			}

			value = context.getName(decoded);
		}

		return lexStrignSuffix(begin, value);
	}

	Token lexString(string s : `"`)() {
		uint l = s.length;
		return lexDecodedString!'"'(index - l);
	}

	/**
	 * Escape sequences.
	 */
	bool lexOctalEscapeSequence(ref DecodedChar decoded) {
		auto c = frontChar;
		if (c < '0' || c > '7') {
			return false;
		}

		uint r = 0;
		foreach (i; 0 .. 3) {
			if (c < '0' || c > '7') {
				break;
			}

			popChar();
			r = (r * 8) | (c - '0');
			c = frontChar;
		}

		if (r > 0xff) {
			// TODO: error: escape octal sequence \NNN is larger than \377
			return false;
		}

		decoded = DecodedChar(char(r & 0xff));
		return true;
	}

	bool decodeNHexCharacters(uint N, T)(ref T result)
			if (N <= 8 && N <= 2 * T.sizeof) {
		if (index + N >= content.length) {
			return false;
		}

		result = 0;

		bool hasError = false;
		foreach (i; 0 .. N) {
			char c = frontChar;
			popChar();

			uint d = c - '0';
			uint h = ((c | 0x20) - 'a') & 0xff;
			uint n = (d < 10) ? d : (h + 10);

			hasError |= n >= 16;
			result |= n << (4 * (N - i - 1));
		}

		return !hasError;
	}

	import source.decodedchar;
	bool lexUnicodeEscapeSequence(char C)(ref DecodedChar decoded)
			if (C == 'u' || C == 'U') {
		enum S = 4 * (C == 'U') + 4;

		popChar();

		dchar v;
		if (!decodeNHexCharacters!S(v)) {
			return false;
		}

		import std.utf;
		if (!isValidDchar(v)) {
			return false;
		}

		decoded = DecodedChar(v);
		return true;
	}

	bool lexEscapeSequence(ref DecodedChar decoded) {
		char c = frontChar;

		switch (c) {
			case '\'', '"', '\\', '?':
				break;

			case '0':
				c = '\0';
				break;

			case '1': .. case '7':
				return lexOctalEscapeSequence(decoded);

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

			case 'x':
				popChar();
				if (!decodeNHexCharacters!2(c)) {
					return false;
				}

				decoded = DecodedChar(c);
				return true;

			case 'u':
				return lexUnicodeEscapeSequence!'u'(decoded);

			case 'U':
				return lexUnicodeEscapeSequence!'U'(decoded);

			case '&':
				assert(0, "HTML5 named character references not implemented");

			default:
				return false;
		}

		popChar();
		decoded = DecodedChar(c);
		return true;
	}
}

unittest {
	import source.context, source.dlexer;
	auto context = new Context();

	auto makeTestLexer(string s) {
		import source.location, source.name;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		return lex(base, context);
	}

	auto checkLexString(string s, string expected) {
		auto lex = makeTestLexer(s);

		import source.parserutil;
		lex.match(TokenType.Begin);

		auto t = lex.match(TokenType.StringLiteral);
		assert(t.decodedString.toString(context) == expected);

		assert(lex.front.type == TokenType.End);
	}

	auto checkLexInvalid(string s, string error) {
		auto lex = makeTestLexer(s);

		import source.parserutil;
		lex.match(TokenType.Begin);

		auto t = lex.match(TokenType.Invalid);
		assert(t.error.toString(context) == error);
	}

	checkLexString(`""`, "");

	// Check unicode support
	checkLexString(`"\U0001F0BD\u0393α\u1FD6\u03B1\U0001FA01🙈🙉🙊\U0001F71A"`,
	               "🂽Γαῖα🨁🙈🙉🙊🜚");

	checkLexInvalid(`"\U0001F0B"`, "Invalid escape sequence.");
	checkLexInvalid(`"\u039"`, "Invalid escape sequence.");
	checkLexInvalid(`"\u039G"`, "Invalid escape sequence.");
	checkLexInvalid(`"\u03@3"`, "Invalid escape sequence.");

	// Check other escaped characters.
	checkLexString(`"\0\a\b\f\r\n\t\v"`, "\0\a\b\f\r\n\t\v");
	checkLexString(`"\xfa\xff\x20\x00\xAA\xf0\xa0"`,
	               "\xfa\xff\x20\x00\xAA\xf0\xa0");
	checkLexString(`"\0\1\11\44\77\111\377"`, "\0\x01\x09\x24\x3f\x49\xff");
	checkLexString(`"\1111\378"`, "\x491\x1f8");

	checkLexInvalid(`"\400"`, "Invalid escape sequence.");
}
