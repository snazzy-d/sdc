module source.lexnumeric;

mixin template LexNumericImpl(
	Token,
	alias IntegralSuffixes,
	alias FloatSuffixes,
	alias CustomIntegralSuffixes = null,
	alias CustomFloatSuffixes = null,
) {
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
			import source.lexbase;
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
		return lexLiteralSuffix!(IntegralSuffixes, CustomIntegralSuffixes)(begin);
	}
	
	Token lexFloatSuffix(uint begin) {
		return lexLiteralSuffix!(FloatSuffixes, CustomFloatSuffixes)(begin);
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
}
