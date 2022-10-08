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

	const offset = location.getStartOffset();
	uint start = offset;

	// This is unexpected end of input.
	if (start == content.length) {
		// Find first non white char.
		import std.ascii;
		while (start > 0 && isWhite(content[start])) {
			start--;
		}
	}

	// XXX: We could probably use infos from source manager here.
	while (start > 0) {
		start--;

		auto c = content[start];
		if (c == '\r' || c == '\n') {
			start++;
			break;
		}
	}

	uint length = location.length;
	uint end = offset + length;

	// This is unexpected end of input.
	if (end > content.length) {
		end = cast(uint) content.length;
	}

	while (end < content.length) {
		auto c = content[end];
		if (c == '\0' || c == '\r' || c == '\n') {
			break;
		}

		end++;
	}

	auto line = content[start .. end];
	uint index = offset - start;

	// Multi line location
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

	assert(index == location.getStartColumn());

	stderr.write(location.isMixin() ? "mixin" : source.getFileName().toString(),
	             ":", location.getStartLineNumber(), ":", index, ":");

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
