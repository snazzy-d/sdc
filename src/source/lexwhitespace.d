module source.lexwhitespace;

enum HorizontalWhiteSpace = [
	// sdfmt off
	" ", "\t",
	"\v", // ??
	"\f", // ??

	// Unicode chapter 6.2, Table 6.2
	"\u00a0", // No break space.
	"\u1680", // Ogham space mark.

	// A bag of spaces of different sizes.
	"\u2000", "\u2001", "\u2002", "\u2003", "\u2004", "\u2005",
	"\u2006", "\u2007", "\u2008", "\u2009", "\u200a",

	"\u202f", // Narrow non breaking space.
	"\u205f", // Medium mathematical space.
	"\u3000", // Ideographic space.
	// sdfmt on
];

enum LineBreaks = [
	// sdfmt off
	"\r", "\n", "\r\n",
	"\u0085", // Next Line.
	"\u2028", // Line Separator.
	"\u2029", // Paragraph Separator.
	// sdfmt on
];

enum WhiteSpaces = HorizontalWhiteSpace ~ LineBreaks;

mixin template LexWhiteSpaceImpl() {
	void popHorizontalWhiteSpaces() {
		static getMap() {
			string[string] ret;

			foreach (op; HorizontalWhiteSpace) {
				ret[op] = "-skip";
			}

			return ret;
		}

		while (true) {
			// Fast track the usual suspects: space and tabs.
			auto c = frontChar;
			while (c == ' ' || c == '\t') {
				popChar();
				c = frontChar;
			}

			import source.lexermixin;
			// pragma(msg, lexerMixin(getMap(), "skip"));
			mixin(lexerMixin(getMap(), "skip"));
		}
	}

	bool popLineBreak() {
		// Special case the end of file:
		// it counts as a line break, but we don't pop it.
		if (reachedEOF()) {
			return true;
		}

		static bool t(string s)() {
			return true;
		}

		static bool f(string s)() {
			return false;
		}

		static getMap() {
			string[string] ret;

			foreach (op; LineBreaks) {
				ret[op] = "t";
			}

			return ret;
		}

		import source.lexermixin;
		// pragma(msg, lexerMixin(getMap(), "f"));
		mixin(lexerMixin(getMap(), "f"));
	}

	void popWhiteSpaces() {
		static getMap() {
			string[string] ret;

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
			// pragma(msg, lexerMixin(getMap(), "skip"));
			mixin(lexerMixin(getMap(), "skip"));
		}
	}

	uint popLine() {
		while (true) {
			ulong state;

			import source.swar.newline;
			while (canSkipOver8CharsInLine(
				       content.ptr[index .. content.length - 1], state)) {
				popChar(8);
			}

			popChar(getSkippableCharsCount(state));

			// canSkipOver8CharsInLine has false positives, such as '\f' and '\v',
			// so we need to check we actually have a line break.
			uint end = index;
			if (popLineBreak()) {
				return end;
			}

			// A false positive, get back to the fast track.
			popChar();
		}
	}
}
