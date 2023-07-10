module source.lexnumeric;

mixin template LexNumericImpl(
	Token,
	alias IntegralSuffixes = ["": "getIntegerLiteral"],
	alias FloatSuffixes = ["": "getFloatLiteral"]
) {
	/**
	 * Integral and float literals.
	 */
	Token lexIntegralSuffix(uint begin, ulong value, bool overflow) {
		return lexLiteralSuffix!IntegralSuffixes(begin, value, overflow);
	}

	Token getIntegerLiteral(string s)(Location location, ulong value,
	                                  bool overflow) {
		if (overflow) {
			return getError(location, "Integral too large to fit in 64 bits.");
		}

		return Token
			.getIntegerLiteral(location, Token.PackedInt.get(context, value));
	}

	Token lexFloatSuffix(bool IsHex)(uint begin, ulong mantissa, bool overflow,
	                                 int exponent) {
		return lexLiteralSuffix!(FloatSuffixes, IsHex)(begin, mantissa,
		                                               overflow, exponent);
	}

	Token lexDecimalFloatSuffix(uint begin, ulong mantissa, bool overflow,
	                            int exponent) {
		return lexFloatSuffix!false(begin, mantissa, overflow, exponent);
	}

	Token lexHexadecimalFloatSuffix(uint begin, ulong mantissa, bool overflow,
	                                int exponent) {
		return lexFloatSuffix!true(begin, mantissa, overflow, exponent);
	}

	Token getHexFloatLiteral()(Location location, ulong mantissa, bool overflow,
	                           int exponent) {
		return
			getFloatLiteral!("", true)(location, mantissa, overflow, exponent);
	}

	Token getFloatLiteral(string s : "", bool IsHex)(
		Location location,
		ulong mantissa,
		bool overflow,
		int exponent,
	) {
		if (overflow) {
			// FIXME: Decode floats with overflowing mantissa.
			return getError(
				location, "Floats with overflowing mantissa are not supported."
			);
		}

		import source.packedfloat;
		auto pf = IsHex
			? Token.PackedFloat.fromHexadecimal(context, mantissa, exponent)
			: Token.PackedFloat.fromDecimal(context, mantissa, exponent);
		return Token.getFloatLiteral(location, pf);
	}

	Token lexFloatLiteral(char E)(uint begin) {
		return decodeLiterals
			? lexFloatLiteral!(E, true)(begin)
			: lexFloatLiteral!(E, false)(begin);
	}

	Token lexFloatLiteral(char E, bool decode)(uint begin) {
		enum IsDec = E == 'e';
		enum IsHex = E == 'p';
		static if (IsDec) {
			import source.util.ascii;
			alias isFun = isDecDigit;
			alias popFun = popDecimal;
			enum ExponentScaleFactor = 1;
		} else static if (IsHex) {
			import source.util.ascii;
			alias isFun = isHexDigit;
			alias popFun = popHexadecimal;
			enum ExponentScaleFactor = 4;
		} else {
			import std.format;
			static assert(0,
			              format!"'%s' is not a valid exponent declarator."(E));
		}

		int exponent = 0;
		ulong mantissa = 0;
		bool overflow = popFun!decode(mantissa);

		bool isFloat = false;
		bool hasExponent = false;

		if (frontChar == '.') {
			auto dotSavePoint = index;

			popChar();
			if (frontChar == '.') {
				index = dotSavePoint;
				goto LexIntegral;
			}

			if (isFun(frontChar)) {
				uint count = 0;
				overflow |= popFun!decode(mantissa, count);
				exponent -= count * ExponentScaleFactor;
				isFloat = true;
				goto LexExponent;
			}

			auto floatSavePoint = index;
			popWhiteSpaces();

			import source.util.identifier;
			if (expectsIdentifier(remainingContent)) {
				index = dotSavePoint;
				goto LexIntegral;
			}

			index = floatSavePoint;
			goto LexFloat;
		}

	LexExponent:
		if ((frontChar | 0x20) == E) {
			isFloat = true;
			hasExponent = true;

			popChar();

			auto c = frontChar;
			bool neg = c == '-';
			if (neg || c == '+') {
				popChar();
			}

			while (frontChar == '_') {
				popChar();
			}

			import source.util.ascii;
			if (!isDecDigit(frontChar)) {
				return getError(begin, "Float literal is missing exponent.");
			}

			ulong value = 0;
			if (popDecimal!decode(value) || value > int.max) {
				// When the exponent overflows, we just make it very large
				// in order to get an infinity after decoding.
				exponent = 0;
				value = int.max;
			}

			import util.math;
			exponent += maybeNegate(value, neg);
		}

		if (isFloat) {
			goto LexFloat;
		}

	LexIntegral:
		return lexIntegralSuffix(begin, mantissa, overflow);

	LexFloat:
		bool isDec = IsDec;
		if (isDec) {
			return lexDecimalFloatSuffix(begin, mantissa, overflow, exponent);
		}

		// Exponent is mandatory for hex floats.
		if (!hasExponent) {
			return getError(begin,
			                "An exponent is mandatory for hexadecimal floats.");
		}

		return lexHexadecimalFloatSuffix(begin, mantissa, overflow, exponent);
	}

	/**
	 * Binary literals.
	 */
	bool popBinary(bool decode)(ref ulong result) {
		uint count = 0;
		return popBinary!decode(result, count);
	}

	bool popBinary(bool decode)(ref ulong result, ref uint count) {
		uint overflow = 0;
		while (true) {
			while (frontChar == '_') {
				popChar();
			}

			import source.swar.bin;

			ulong state;
			while (startsWith8BinDigits(remainingContent, state)) {
				if (decode) {
					overflow |= result >> 56;
					result <<= 8;
					result |= decodeBinDigits(remainingContent);
				}

				count += 8;
				popChar(8);
			}

			if (hasMoreDigits(state)) {
				auto digitCount = getDigitCount(state);
				if (decode) {
					overflow |= result >> (64 - digitCount);
					result <<= digitCount;
					result |= decodeBinDigits(remainingContent, digitCount);
				}

				count += digitCount;
				popChar(digitCount);
			}

			if (frontChar != '_') {
				return overflow != 0;
			}

			popChar();
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

		auto c = frontChar;
		if (c != '0' && c != '1') {
			import std.format;
			return getError(
				begin,
				format!"%s is not a valid binary literal."(
					content[begin .. index])
			);
		}

		ulong value = 0;
		auto overflow =
			decodeLiterals ? popBinary!true(value) : popBinary!false(value);

		return lexIntegralSuffix(begin, value, overflow);
	}

	/**
	 * Hexadecimal literals.
	 */
	bool popHexadecimal(bool decode)(ref ulong result) {
		uint count = 0;
		return popHexadecimal!decode(result, count);
	}

	bool popHexadecimal(bool decode)(ref ulong result, ref uint count) {
		uint overflow = 0;
		while (true) {
			while (frontChar == '_') {
				popChar();
			}

			import source.swar.hex;

			ulong state;
			while (startsWith8HexDigits(remainingContent, state)) {
				if (decode) {
					overflow |= result >> 32;
					result <<= 32;
					result |= decodeHexDigits!uint(remainingContent);
				}

				count += 8;
				popChar(8);
			}

			if (hasMoreDigits(state)) {
				auto digitCount = getDigitCount(state);
				if (decode) {
					auto shift = 4 * digitCount;
					overflow |= result >> (64 - shift);
					result <<= shift;
					result |= decodeHexDigits(remainingContent, digitCount);
				}

				count += digitCount;
				popChar(digitCount);
			}

			if (frontChar != '_') {
				return overflow != 0;
			}

			popChar();
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

		auto c = frontChar;

		import source.util.ascii;
		if (isHexDigit(c) || (c == '.' && isHexDigit(nextChar))) {
			return lexFloatLiteral!'p'(begin);
		}

		import std.format;
		return getError(
			begin,
			format!"%s is not a valid hexmadecimal literal."(
				content[begin .. index])
		);
	}

	/**
	 * Decimal literals.
	 */
	bool popDecimal(bool decode)(ref ulong result) {
		uint count = 0;
		return popDecimal!decode(result, count);
	}

	bool popDecimal(bool decode)(ref ulong result, ref uint count) {
		ulong overflow = 0;
		while (true) {
			while (frontChar == '_') {
				popChar();
			}

			import source.swar.dec, util.math;

			ulong state;
			while (startsWith8DecDigits(remainingContent, state)) {
				if (decode) {
					auto scaled = result * 100000000;
					auto next = decodeDecDigits!uint(remainingContent);

					overflow |= mulhi(result, 100000000);
					result = next + scaled;
					overflow |= result < scaled;
				}

				count += 8;
				popChar(8);
			}

			if (hasMoreDigits(state)) {
				static immutable uint[8] POWERS_OF_10 =
					[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000];

				auto digitCount = getDigitCount(state);
				if (decode) {
					auto p10 = POWERS_OF_10[digitCount];
					auto scaled = result * p10;
					auto next = decodeDecDigits(remainingContent, digitCount);

					overflow |= mulhi(result, p10);
					result = next + scaled;
					overflow |= result < scaled;
				}

				count += digitCount;
				popChar(digitCount);
			}

			if (frontChar != '_') {
				return overflow != 0;
			}

			popChar();
		}
	}

	auto lexNumeric(string s)() if (s.length == 1) {
		import source.util.ascii;
		static assert(isDecDigit(s[0]), "Expected Decimal character.");

		index -= s.length;
		return lexDecimal();
	}

	auto lexNumeric(string s)() if (s.length == 2 && s[0] == '.') {
		import source.util.ascii;
		static assert(isDecDigit(s[1]), "Expected Decimal character.");

		index -= s.length;
		return lexDecimal();
	}

	auto lexDecimal() {
		return lexFloatLiteral!'e'(index);
	}
}

auto registerNumericPrefixes(string[string] lexerMap) {
	foreach (i; 0 .. 10) {
		import std.conv;
		auto s = to!string(i);
		lexerMap[s] = "lexNumeric";
		lexerMap["." ~ s] = "lexNumeric";
	}

	return lexerMap;
}

unittest {
	import source.context, source.dlexer;
	auto context = new Context();

	auto makeTestLexer(string s) {
		import source.location;
		auto base = context.registerMixin(Location.init, s ~ '\0');
		return lex(base, context);
	}

	auto checkLexIntegral(string s, ulong expected) {
		auto lex = makeTestLexer(s);

		import source.parserutil;
		lex.match(TokenType.Begin);

		// FIXME: Handle overflow cases.
		auto t = lex.match(TokenType.IntegerLiteral);
		assert(t.packedInt.toInt(context) == expected);

		assert(lex.front.type == TokenType.End);
		assert(lex.index == s.length + 1);
	}

	auto checkLexFloat(string s, double expected) {
		auto lex = makeTestLexer(s);

		import source.parserutil;
		lex.match(TokenType.Begin);

		auto t = lex.match(TokenType.FloatLiteral);
		assert(t.packedFloat.to!double(context) is expected, s);

		import std.array;
		auto str =
			t.location.getFullLocation(context).getSlice().replace("_", "")
				~ '\0';

		import core.stdc.stdlib;
		assert(strtod(str.ptr, null) is expected);

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

	auto checkTokenSequence(string s, TokenType[] tokenTypes) {
		auto lex = makeTestLexer(s);

		import source.parserutil;
		lex.match(TokenType.Begin);

		foreach (t; tokenTypes) {
			lex.match(t);
		}

		assert(lex.front.type == TokenType.End);
		assert(lex.index == s.length + 1);
	}

	// Various integrals.
	checkLexIntegral("0", 0);
	checkLexIntegral("0x0", 0);
	checkLexIntegral("0b0", 0);
	checkLexIntegral("000000000000000000", 0);
	checkLexIntegral("0x0000000000000000", 0);
	checkLexIntegral("0b0000000000000000", 0);

	checkLexIntegral("1", 1);
	checkLexIntegral("0x1", 1);
	checkLexIntegral("0b1", 1);
	checkLexIntegral("000000000000000001", 1);
	checkLexIntegral("0x0000000000000001", 1);
	checkLexIntegral("0b0000000000000001", 1);

	checkLexIntegral("2", 2);
	checkLexIntegral("0x2", 2);
	checkLexIntegral("0b10", 2);
	checkLexIntegral("000000000000000002", 2);
	checkLexIntegral("0x0000000000000002", 2);
	checkLexIntegral("0b0000000000000010", 2);

	checkLexIntegral("15", 15);
	checkLexIntegral("0xf", 15);
	checkLexIntegral("0b1111", 15);
	checkLexIntegral("000000000000000015", 15);
	checkLexIntegral("0x000000000000000f", 15);
	checkLexIntegral("0b0000000000001111", 15);

	checkLexIntegral("42", 42);
	checkLexIntegral("0x2a", 42);
	checkLexIntegral("0x2A", 42);
	checkLexIntegral("0b101010", 42);
	checkLexIntegral("000000000000000042", 42);
	checkLexIntegral("0x000000000000002a", 42);
	checkLexIntegral("0x000000000000002A", 42);
	checkLexIntegral("0b0000000000101010", 42);

	checkLexIntegral("11400714819323198485", 11400714819323198485);
	checkLexIntegral("0x9e3779b97f4a7c15", 11400714819323198485);
	checkLexIntegral(
		"0b1001111000110111011110011011100101111111010010100111110000010101",
		11400714819323198485);

	checkLexIntegral("13782704132928070901", 13782704132928070901);
	checkLexIntegral("0xbf4600628f7c64f5", 13782704132928070901);
	checkLexIntegral(
		"0b1011111101000110000000000110001010001111011111000110010011110101",
		13782704132928070901);

	checkLexIntegral("14181476777654086739", 14181476777654086739);
	checkLexIntegral("0xc4ceb9fe1a85ec53", 14181476777654086739);
	checkLexIntegral(
		"0b1100010011001110101110011111111000011010100001011110110001010011",
		14181476777654086739);

	checkLexIntegral("18397679294719823053", 18397679294719823053);
	checkLexIntegral("0xff51afd7ed558ccd", 18397679294719823053);
	checkLexIntegral(
		"0b1111111101010001101011111101011111101101010101011000110011001101",
		18397679294719823053);

	checkLexIntegral("1844674407370955161", 1844674407370955161);
	checkLexIntegral("0x1999999999999999", 1844674407370955161);
	checkLexIntegral(
		"0b1100110011001100110011001100110011001100110011001100110011001",
		1844674407370955161);

	checkLexIntegral("12297829382473034410", 12297829382473034410);
	checkLexIntegral("0xaaaaaaaaaaaaaaaa", 12297829382473034410);
	checkLexIntegral(
		"0b1010101010101010101010101010101010101010101010101010101010101010",
		12297829382473034410);

	checkLexIntegral("6148914691236517205", 6148914691236517205);
	checkLexIntegral("0x5555555555555555", 6148914691236517205);
	checkLexIntegral(
		"0b0101010101010101010101010101010101010101010101010101010101010101",
		6148914691236517205);

	checkLexIntegral("18446744073709551615", 18446744073709551615);
	checkLexIntegral("0xffffffffffffffff", 18446744073709551615);
	checkLexIntegral(
		"0b1111111111111111111111111111111111111111111111111111111111111111",
		18446744073709551615);

	// Underscore.
	checkLexIntegral("1_", 1);
	checkLexIntegral("1_1", 11);
	checkLexIntegral("11_11", 1111);
	checkLexIntegral("1_2_3_4_5", 12345);
	checkLexIntegral("34_56", 3456);

	checkLexIntegral("0x_01", 1);
	checkLexIntegral("0x0_1", 1);
	checkLexIntegral("0x01_", 1);
	checkLexIntegral("0xa_B_c", 2748);

	checkLexIntegral("0b_01", 1);
	checkLexIntegral("0b0_1", 1);
	checkLexIntegral("0b01_", 1);
	checkLexIntegral("0b11_101_00", 116);

	checkTokenSequence("_1", [TokenType.Identifier]);
	checkTokenSequence("_0x01", [TokenType.Identifier]);
	checkTokenSequence("_0b01", [TokenType.Identifier]);

	checkLexInvalid("0x", "0x is not a valid hexmadecimal literal.");
	checkLexInvalid("0x_", "0x_ is not a valid hexmadecimal literal.");
	checkLexInvalid("0x__", "0x__ is not a valid hexmadecimal literal.");

	checkLexInvalid("0b", "0b is not a valid binary literal.");
	checkLexInvalid("0b_", "0b_ is not a valid binary literal.");
	checkLexInvalid("0b__", "0b__ is not a valid binary literal.");

	// Suffixes.
	checkLexInvalid("0_x", "`x` is not a valid suffix.");
	checkLexInvalid("0_x_", "`x_` is not a valid suffix.");

	checkLexInvalid("0_b", "`b` is not a valid suffix.");
	checkLexInvalid("0_b_", "`b_` is not a valid suffix.");

	checkLexInvalid("0b2", "0b is not a valid binary literal.");
	checkLexInvalid("0b12", "`2` is not a valid suffix.");

	// Decimal cases.
	checkLexIntegral("1234567890", 1234567890);
	checkLexIntegral("18446744073709551615", 18446744073709551615);

	// Hexadecimal cases.
	checkLexIntegral("0xAbCdEf0", 180150000);
	checkLexIntegral("0x12345aBcDeF", 1251004370415);
	checkLexIntegral("0x12345aBcDeF0", 20016069926640);

	// Overflow.
	checkLexIntegral("18446744073709551615", ulong.max);
	checkLexInvalid("18446744073709551616",
	                "Integral too large to fit in 64 bits.");
	checkLexInvalid("1844674407370955161500000000",
	                "Integral too large to fit in 64 bits.");

	checkLexIntegral(
		"0b1111111111111111111111111111111111111111111111111111111111111111",
		ulong.max
	);
	checkLexInvalid(
		"0b10000000000000000000000000000000000000000000000000000000000000000",
		"Integral too large to fit in 64 bits.");
	checkLexInvalid(
		"0b111111111111111111111111111111111111111111111111111111111111111100000000",
		"Integral too large to fit in 64 bits.");

	checkLexIntegral("0xffffffffffffffff", ulong.max);
	checkLexInvalid("0x10000000000000000",
	                "Integral too large to fit in 64 bits.");
	checkLexInvalid("0xffffffffffffffff00000000",
	                "Integral too large to fit in 64 bits.");

	checkLexFloat("1e2147483647", float.infinity);
	checkLexFloat("1e2147483648", float.infinity);
	checkLexFloat("1e18446744073709551615", float.infinity);
	checkLexFloat("1e18446744073709551616", float.infinity);

	checkLexFloat("1e-2147483647", 0);
	checkLexFloat("1e-2147483648", 0);
	checkLexFloat("1e-18446744073709551615", 0);
	checkLexFloat("1e-18446744073709551615", 0);

	// Decimal floats.
	checkLexFloat("1.", 1);
	checkLexFloat("1.0", 1);
	checkLexFloat("01.", 1);
	checkLexFloat("01.0", 1);

	checkLexFloat("1e0", 1);
	checkLexFloat("1e+0", 1);
	checkLexFloat("1e-0", 1);
	checkLexFloat("1.0e0", 1);
	checkLexFloat("1.0e+0", 1);
	checkLexFloat("1.0e-0", 1);

	checkLexFloat("1E0", 1);
	checkLexFloat("1E+0", 1);
	checkLexFloat("1E-0", 1);
	checkLexFloat("1.0E0", 1);
	checkLexFloat("1.0E+0", 1);
	checkLexFloat("1.0E-0", 1);

	checkLexInvalid("1e", "Float literal is missing exponent.");
	checkLexInvalid("1e+", "Float literal is missing exponent.");
	checkLexInvalid("1e-", "Float literal is missing exponent.");

	checkLexInvalid("1E", "Float literal is missing exponent.");
	checkLexInvalid("1E+", "Float literal is missing exponent.");
	checkLexInvalid("1E-", "Float literal is missing exponent.");

	checkLexFloat("42e0", 42);
	checkLexFloat("42e1", 420);
	checkLexFloat("42e-1", 4.2);
	checkLexFloat("42e+1", 420);

	checkLexFloat("1.5e0", 1.5);
	checkLexFloat("1.5e1", 15);
	checkLexFloat("1.5e+1", 15);
	checkLexFloat("1.5e-1", 0.15);

	checkLexFloat(".0", 0);
	checkLexFloat(".5", 0.5);
	checkLexFloat(".6e0", 0.6);
	checkLexFloat(".7e1", 7);
	checkLexFloat(".8e+1", 8);
	checkLexFloat(".9e-1", 0.09);

	checkLexFloat("1234567.89", 1234567.89);
	checkLexFloat("12.3456789", 12.3456789);

	/*
	checkLexFloat("3.141592653589793115997963468544185161590576171875",
	              3.141592653589793115997963468544185161590576171875);
	checkLexFloat("3.321928094887362181708567732130177319049835205078125",
	              3.321928094887362181708567732130177319049835205078125);
	/*/
	// FIXME: Decode floats with overflowing mantissa.
	checkLexInvalid("3.141592653589793115997963468544185161590576171875",
	                "Floats with overflowing mantissa are not supported.");
	checkLexInvalid("3.321928094887362181708567732130177319049835205078125",
	                "Floats with overflowing mantissa are not supported.");
	//*/

	// Decimal floats with underscores.
	checkLexFloat("1_234_567.89", 1234567.89);
	checkLexFloat("1_2.34_567_89", 12.3456789);
	checkLexFloat("1_234_567.89", 1234567.89);
	checkLexFloat("1_2.34_567_89", 12.3456789);

	checkLexFloat("1_234_567_.89", 1234567.89);
	checkLexFloat("1_234_567.89_", 1234567.89);

	checkTokenSequence("_1_234_567.89",
	                   [TokenType.Identifier, TokenType.FloatLiteral]);
	checkTokenSequence(
		"1_234_567._89",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);

	checkLexFloat("42e_1", 420);
	checkLexFloat("42e1_", 420);
	checkLexFloat("42e_1_", 420);
	checkLexFloat("42e+_1", 420);
	checkLexFloat("42e+1_", 420);
	checkLexFloat("42e+_1_", 420);
	checkLexFloat("42e-_1", 4.2);
	checkLexFloat("42e-1_", 4.2);
	checkLexFloat("42e-_1_", 4.2);

	checkLexInvalid("1e_", "Float literal is missing exponent.");
	checkLexInvalid("1e+_", "Float literal is missing exponent.");
	checkLexInvalid("1e-_", "Float literal is missing exponent.");

	checkLexInvalid("1e_+0", "Float literal is missing exponent.");
	checkLexInvalid("1e_-0", "Float literal is missing exponent.");

	// Space within decimal floats.
	checkTokenSequence("1. 0",
	                   [TokenType.FloatLiteral, TokenType.IntegerLiteral]);
	checkTokenSequence("1 .0",
	                   [TokenType.IntegerLiteral, TokenType.FloatLiteral]);
	checkTokenSequence(
		"1 . 0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.IntegerLiteral]
	);
	checkTokenSequence(
		"1..0",
		[TokenType.IntegerLiteral, TokenType.DotDot, TokenType.IntegerLiteral]
	);

	checkTokenSequence("1. .0",
	                   [TokenType.FloatLiteral, TokenType.FloatLiteral]);
	checkTokenSequence("1e 0", [TokenType.Invalid, TokenType.IntegerLiteral]);
	checkTokenSequence("1 e0",
	                   [TokenType.IntegerLiteral, TokenType.Identifier]);

	checkTokenSequence("1e+ 0", [TokenType.Invalid, TokenType.IntegerLiteral]);
	checkTokenSequence("1e- 0", [TokenType.Invalid, TokenType.IntegerLiteral]);
	checkTokenSequence(
		"1e +0", [TokenType.Invalid, TokenType.Plus, TokenType.IntegerLiteral]);
	checkTokenSequence(
		"1e -0",
		[TokenType.Invalid, TokenType.Minus, TokenType.IntegerLiteral]
	);
	checkTokenSequence(
		"1 e+0",
		[TokenType.IntegerLiteral, TokenType.Identifier, TokenType.Plus,
		 TokenType.IntegerLiteral]
	);
	checkTokenSequence(
		"1 e-0",
		[TokenType.IntegerLiteral, TokenType.Identifier, TokenType.Minus,
		 TokenType.IntegerLiteral]
	);

	checkTokenSequence(
		"1.f", [TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]);
	checkTokenSequence(
		"1.e0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence(
		"1. e0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence(
		"1. .e0",
		[TokenType.FloatLiteral, TokenType.Dot, TokenType.Identifier]
	);

	// Hexadecimal floats.
	checkLexFloat("0x1p0", 1);
	checkLexFloat("0x1p+0", 1);
	checkLexFloat("0x1p-0", 1);
	checkLexFloat("0x1.0p0", 1);
	checkLexFloat("0x1.0p+0", 1);
	checkLexFloat("0x1.0p-0", 1);

	checkLexFloat("0x1P0", 1);
	checkLexFloat("0x1P+0", 1);
	checkLexFloat("0x1P-0", 1);
	checkLexFloat("0x1.0P0", 1);
	checkLexFloat("0x1.0P+0", 1);
	checkLexFloat("0x1.0P-0", 1);

	checkLexInvalid("0x1p", "Float literal is missing exponent.");
	checkLexInvalid("0x1p+", "Float literal is missing exponent.");
	checkLexInvalid("0x1p-", "Float literal is missing exponent.");

	checkLexInvalid("0x1P", "Float literal is missing exponent.");
	checkLexInvalid("0x1P+", "Float literal is missing exponent.");
	checkLexInvalid("0x1P-", "Float literal is missing exponent.");

	checkLexFloat("0xa.ap0", 10.625);
	checkLexFloat("0xa.ap1", 21.25);
	checkLexFloat("0xa.ap+1", 21.25);
	checkLexFloat("0xa.ap-1", 5.3125);

	/*
	checkLexFloat("0x1.921fb54442d1846ap+1",
	              3.141592653589793115997963468544185161590576171875);
	checkLexFloat("0x1.a934f0979a3715fcp+1",
	              3.321928094887362181708567732130177319049835205078125);
	/*/
	// FIXME: Decode floats with overflowing mantissa.
	checkLexInvalid("0x1.921fb54442d1846ap+1",
	                "Floats with overflowing mantissa are not supported.");
	checkLexInvalid("0x1.a934f0979a3715fcp+1",
	                "Floats with overflowing mantissa are not supported.");

	//*/

	checkLexFloat("0x123456.abcdefp0", 1193046.671111047267913818359375);
	checkLexFloat("0x1_23_456.abc_defp0", 1193046.671111047267913818359375);
	checkLexFloat("0x1_23_456_.abc_defp0", 1193046.671111047267913818359375);
	checkLexFloat("0x1_23_456.abc_def_p0", 1193046.671111047267913818359375);
	checkLexFloat("0x_1_23_456.abc_defp0", 1193046.671111047267913818359375);

	checkLexFloat("0xa.ap_0", 10.625);
	checkLexFloat("0xa.ap0_", 10.625);
	checkLexFloat("0xa.ap_0_", 10.625);
	checkLexFloat("0xa.ap+_1", 21.25);
	checkLexFloat("0xa.ap+1_", 21.25);
	checkLexFloat("0xa.ap+_1_", 21.25);
	checkLexFloat("0xa.ap-_1", 5.3125);
	checkLexFloat("0xa.ap-1_", 5.3125);
	checkLexFloat("0xa.ap-_1_", 5.3125);

	checkLexInvalid("0xa.ap_+1", "Float literal is missing exponent.");
	checkLexInvalid("0xa.ap_-1", "Float literal is missing exponent.");

	checkTokenSequence(
		"0xa._ap0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);

	checkLexFloat("0x.ap0", 0.625);
	checkLexFloat("0x.ap1", 1.25);
	checkLexFloat("0x.ap+1", 1.25);
	checkLexFloat("0x.ap-1", 0.3125);

	checkLexFloat("0x_.ap0", 0.625);
	checkLexFloat("0x.a_p0", 0.625);
	checkLexFloat("0x.ap_0", 0.625);
	checkLexFloat("0x.ap0_", 0.625);
	checkLexFloat("0x.ap+_1", 1.25);
	checkLexFloat("0x.ap+1_", 1.25);

	checkLexInvalid("0x.ap_+1", "Float literal is missing exponent.");
	checkLexInvalid("0x.ap_-1", "Float literal is missing exponent.");

	checkTokenSequence(
		"0x._ap0", [TokenType.Invalid, TokenType.Dot, TokenType.Identifier]);
	checkTokenSequence(
		"0x.ap_+1",
		[TokenType.Invalid, TokenType.Plus, TokenType.IntegerLiteral]
	);
	checkTokenSequence(
		"0x.ap_-1",
		[TokenType.Invalid, TokenType.Minus, TokenType.IntegerLiteral]
	);

	// Exponent is mandatory for hexadecimal floats.
	checkLexInvalid("0x1.0",
	                "An exponent is mandatory for hexadecimal floats.");
	checkLexInvalid("0x.a", "An exponent is mandatory for hexadecimal floats.");

	// Spaces within hexadecimal floats.
	checkTokenSequence("0x ap0", [TokenType.Invalid, TokenType.Identifier]);
	checkTokenSequence("0xap 0", [TokenType.Invalid, TokenType.IntegerLiteral]);
	checkTokenSequence(
		"0x. ap0", [TokenType.Invalid, TokenType.Dot, TokenType.Identifier]);
	checkTokenSequence("0x.a p0", [TokenType.Invalid, TokenType.Identifier]);
	checkTokenSequence("0x.ap 0",
	                   [TokenType.Invalid, TokenType.IntegerLiteral]);
	checkTokenSequence(
		"0x a.ap0",
		[TokenType.Invalid, TokenType.Identifier, TokenType.Dot,
		 TokenType.Identifier]
	);
	checkTokenSequence(
		"0xa .ap0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence(
		"0xa. ap0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence("0xa.ap 0",
	                   [TokenType.Invalid, TokenType.IntegerLiteral]);

	checkTokenSequence(
		"0x1.l",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence(
		"0x1.p0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence(
		"0x1. p0",
		[TokenType.IntegerLiteral, TokenType.Dot, TokenType.Identifier]
	);
	checkTokenSequence(
		"0x1. .p0", [TokenType.Invalid, TokenType.Dot, TokenType.Identifier]);
}
