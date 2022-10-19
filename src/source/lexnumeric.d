module source.lexnumeric;

mixin template LexNumericImpl(
	Token,
	alias IntegralSuffixes = ["" : "getIntegerLiteral"],
	alias FloatSuffixes = ["" : "getFloatLiteral"]
) {
	/**
	 * Integral and float literals.
	 */
	Token lexIntegralSuffix(uint begin, ulong value) {
		return lexLiteralSuffix!IntegralSuffixes(begin, value);
	}

	Token getIntegerLiteral(string s : "")(Location location, ulong value) {
		return Token.getIntegerLiteral(location, value);
	}

	Token lexFloatSuffix(uint begin, double value) {
		return lexLiteralSuffix!FloatSuffixes(begin, value);
	}

	Token getFloatLiteral(string s : "")(Location location, double value) {
		return Token.getFloatLiteral(location, value);
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

			popWhiteSpaces();

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

			popDecimal();
		}

	LexSuffix:
		if (isFloat) {
			return lexFloatSuffix(begin, 0);
		}

		ulong value = 0;
		if (decodeLiterals) {
			import source.strtoint;
			value = strToInt(content[begin .. index]);
		}

		return lexIntegralSuffix(begin, value);
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

		if (!isBinary(frontChar)) {
			return getError(begin, "Invalid binary sequence.");
		}

		popBinary();

		ulong value = 0;
		if (decodeLiterals) {
			import source.strtoint;
			value = strToBinInt(content[begin + 2 .. index]);
		}

		return lexIntegralSuffix(begin, value);
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

		if (!isHexadecimal(frontChar)) {
			return getError(begin, "Invalid hexadecimal sequence.");
		}

		return lexFloatLiteral!(isHexadecimal, popHexadecimal, 'p')(begin);
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

	auto lexNumeric(char c) in(isDecimal(c)) {
		return lexFloatLiteral!(isDecimal, popDecimal, 'e')(index - 1);
	}
}
