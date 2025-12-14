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

	auto offset = location.getStartOffset();
	if (offset >= content.length) {
		offset = cast(uint) content.length - 1;
	}

	auto indexPosition = source.getWithOffset(offset);
	uint start = indexPosition.getStartOfLine().getSourceOffset();

	uint end = location.getStopOffset();

	// This is unexpected end of input.
	if (end > content.length) {
		end = cast(uint) content.length;
	}

	// Trim end of line if apropriate.
	while (end > start) {
		end--;

		auto c = content[end];
		if (c != '\r' && c != '\n') {
			end++;
			break;
		}
	}

	// Extend the range up to the end of the line.
	while (end < content.length) {
		auto c = content[end];
		if (c == '\r' || c == '\n') {
			break;
		}

		end++;
	}

	auto line = content[start .. end];

	uint index = offset - start;
	uint length = location.length;

	// Multi line location.
	if (index < line.length && index + length > line.length) {
		length = cast(uint) line.length - index;
	}

	char[] underline;
	underline.length = index + length;
	foreach (i; 0 .. index) {
		underline[i] = (line[i] == '\t') ? '\t' : ' ';
	}

	underline[index] = '^';
	foreach (i; index + 1 .. index + length) {
		underline[i] = '~';
	}

	assert(index == indexPosition.getColumn());

	stderr.write(location.isMixin() ? "mixin" : source.getFileName().toString(),
	             ":", indexPosition.getLineNumber(), ":", index, ":");

	stderr.writeColouredText(ConsoleColour.Red, " error: ");
	stderr.writeColouredText(ConsoleColour.White, fixHint, "\n");

	stderr.writeln(line);
	stderr.writeColouredText(ConsoleColour.Green, underline, "\n");

	if (location.isMixin()) {
		outputCaretDiagnostics(source.getImportLocation(), "mixed in at");
	}
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
