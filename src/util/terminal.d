module util.terminal;

import std.stdio;

import source.location;

version(Windows) {
	import core.sys.windows.windows;
}

void outputCaretDiagnostics(FullLocation location, string fixHint) {
	import std.stdio;
	auto source = location.getSource();
	auto content = source.getContent();

	auto first = location.getStartOffset();
	if (first >= content.length) {
		/**
		 * This typically happens when the input ends unexpectedly.
		 * In this situation, we want to display the last line of the input
		 * and put the carret at the end of that line.
		 */
		first = cast(uint) content.length - 1;
	}

	auto startp = source.getWithOffset(first);
	auto nline = startp.getLineNumber();
	uint current = source.getLineOffset(nline).getSourceOffset();

	uint column = first - current;
	assert(column == startp.getColumn());

	stderr.write(location.isMixin() ? "mixin" : source.getFileName().toString(),
	             ":", nline + 1, ":", column, ":");

	stderr.writeColouredText(ConsoleColour.Red, " error: ");
	stderr.writeColouredText(ConsoleColour.White, fixHint, "\n");

	uint last = location.getStopOffset();
	if (last > content.length) {
		/**
		 * FIXME: I'm pretty sure we should consider this happening a bug.
		 *        As far as I'm aware, the only case it is happening is when
		 *        we generate an End token in the lexer, and we could make
		 *        it zero length and avoid this special case.
		 */
		last = cast(uint) content.length;
	}

	while (current < last) {
		uint next = source.getLineOffset(++nline).getSourceOffset();
		scope(success) current = next;

		// Trim end of line if apropriate.
		uint end = backTrackLineBreak(content, next);
		auto line = content[current .. end];

		auto c = current < first ? first - current : 0;
		auto length = end > last ? last - current : line.length;

		char[] underline;
		underline.length = length;

		foreach (i; 0 .. c) {
			underline[i] = (line[i] == '\t') ? '\t' : ' ';
		}

		auto printCarret = current <= first;
		if (printCarret) {
			underline[c] = '^';
		}

		foreach (i; c + printCarret .. length) {
			underline[i] = '~';
		}

		stderr.writeln(line);
		stderr.writeColouredText(ConsoleColour.Green, underline, "\n");
	}

	if (location.isMixin()) {
		outputCaretDiagnostics(source.getImportLocation(), "mixed in at");
	}
}

template LineBreaksOfLength(uint N) {
	import source.lexwhitespace;
	import std.array, std.algorithm;
	enum LineBreaksOfLength = LineBreaks.filter!(op => op.length == N).array();
}

uint backTrackLineBreak(string content, uint index)
		in(index <= content.length && content.length < uint.max) {
	static foreach_reverse (N; 1 .. 4) {
		if (index >= N) {
			auto suffix = content[index - N .. index];
			static foreach (op; LineBreaksOfLength!N) {
				if (suffix == op) {
					return index - N;
				}
			}
		}
	}

	// No match.
	return index;
}

unittest {
	void check(string s) {
		auto l = cast(uint) s.length;
		assert(backTrackLineBreak(s, l) == l);

		import source.lexwhitespace;
		foreach (op; LineBreaks) {
			auto c = s ~ op;
			auto cl = cast(uint) c.length;

			assert(backTrackLineBreak(c, cl) == l);
			assert(backTrackLineBreak(c, cl - 1) == cl - 1 - (op == "\r\n"));

			c ~= '0';
			assert(backTrackLineBreak(c, cl) == l);
			assert(backTrackLineBreak(c, cl + 1) == cl + 1);
		}
	}

	check("");
	check("0");
	check("00");
}

/**
 * ANSI colour codes per ECMA-48 (minus 30).
 * e.g., Yellow = 3 + 30 = 33.
 */
enum ConsoleColour {
	Black = 0,
	Red = 1,
	Green = 2,
	Yellow = 3,
	Blue = 4,
	Magenta = 5,
	Cyan = 6,
	White = 7,
}

void writeColouredText(T...)(File pipe, ConsoleColour colour, T t) {
	bool coloursEnabled = true; // XXX: Fix me!

	if (!coloursEnabled) {
		pipe.write(t);
	}

	char[5] ansiSequence = [0x1b, '[', '3', '0', 'm'];
	ansiSequence[3] = cast(char) (colour + '0');

	// XXX: use \e]11;?\a to get the color to restore
	pipe.write(ansiSequence, t, "\x1b[0m");
}
