module source.lexermixin;

string lexerMixin(string[string] ids, string def = "lexDefaultFallback",
                  string[] rtArgs = []) {
	return lexerMixin(ids, def, rtArgs, "");
}

private:

string toCharLit(char c) {
	switch (c) {
		case '\0':
			return "\\0";

		case '\'':
			return "\\'";

		case '"':
			return "\\\"";

		case '\\':
			return "\\\\";

		case '\a':
			return "\\a";

		case '\b':
			return "\\b";

		case '\t':
			return "\\t";

		case '\v':
			return "\\v";

		case '\f':
			return "\\f";

		case '\n':
			return "\\n";

		case '\r':
			return "\\r";

		default:
			import std.ascii;
			if (isPrintable(c)) {
				return [c];
			}

			static char toHexChar(ubyte n) {
				return ((n < 10) ? (n + '0') : (n - 10 + 'a')) & 0xff;
			}

			static string toHexString(ubyte c) {
				return [toHexChar(c >> 4), toHexChar(c & 0x0f)];
			}

			return "\\x" ~ toHexString(c);
	}
}

auto stringify(string s) {
	import std.algorithm, std.format, std.string;
	return format!`"%-(%s%)"`(s.representation.map!(c => toCharLit(c)));
}

auto getLexingCode(string fun, string[] rtArgs, string base) {
	import std.format;
	auto args = format!"(%-(%s, %))"(rtArgs);

	static getFun(string fun, string base) {
		return format!"%s!%s"(fun, stringify(base));
	}

	switch (fun[0]) {
		case '-':
			return format!"
				%s%s;
				continue;"(getFun(fun[1 .. $], base), args);

		case '?':
			return format!"
				auto t = lex%s%s;
				if (skip%1$s(t)) {
					continue;
				}

				return t;"(getFun(fun[1 .. $], base), args);

		default:
			return format!"
				return %s%s;"(getFun(fun, base), args);
	}
}

string lexerMixin(string[string] ids, string def, string[] rtArgs,
                  string base) {
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
		import std.format;
		ret ~= format!"
			case '%s':
				popChar();"(toCharLit(c));

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
		import std.format;
		ret ~= format!"
			default:%s
		}
		"(getLexingCode(defaultFun, rtArgs, base));
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
