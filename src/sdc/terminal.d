/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.terminal;

import std.stdio;

import d.location;

version(Windows) {
	import std.c.windows.windows;
}

void outputCaretDiagnostics(Location loc, string fixHint) {
	uint start = loc.index;
	auto content = loc.source.content;

	// This is unexpected end of input.
	if (start == content.length) {
		// Find first non white char.
		import std.ascii;
		while(start > 0 && isWhite(content[--start])) {}
	}
	
	FindStart: while(start > 0) {
		switch(content[start]) {
			case '\n':
			case '\r':
				start++;
				break FindStart;
			
			default:
				start--;
		}
	}
	
	uint end = loc.index + loc.length;
	
	// This is unexpected end of input.
	if(end > content.length) {
		end = cast(uint) content.length;
	}
	
	FindEnd: while(end < content.length) {
		switch(content[end]) {
			case '\n':
			case '\r':
				break FindEnd;
			
			default:
				end++;
		}
	}
	
	auto line = content[start .. end];
	uint index = loc.index - start;
	uint length = loc.length;
	
	// Multi line location
	if(index < line.length && index + length > line.length) {
		length = cast(uint) line.length - index;
	}
	
	writeColouredText(stderr, ConsoleColour.Green, {
		stderr.writeln(line);
	});
	
	char[] underline;
	underline.length = index + length;
	foreach(i; 0 .. index) {
		underline[i] = (line[i] == '\t') ? '\t' : ' ';
	}
	
	underline[index] = '^';
	foreach(i; index + 1 .. index + length) {
		underline[i] = '~';
	}
	
	writeColouredText(stderr, ConsoleColour.Yellow, {
		stderr.writeln(underline);
	});
	
	if(fixHint !is null) {
		writeColouredText(stderr, ConsoleColour.Yellow, {
			stderr.writeln(underline[0 .. index], fixHint);
		});
	}
	
	if(auto fileSource = cast(FileSource) loc.source) {
		writeColouredText(stderr, ConsoleColour.Blue, {
			stderr.writeln(fileSource.filename, " line ", loc.line);
		});
	} else if(auto mixinSource = cast(MixinSource) loc.source) {
		writeColouredText(stderr, ConsoleColour.Blue, {
			stderr.writeln("Line ", loc.line, " expanded from mixin :");
		});
		
		outputCaretDiagnostics(mixinSource.location, null);
	}
}

version(Windows) {
	enum ConsoleColour : WORD {
		Red		= FOREGROUND_RED,
		Green	= FOREGROUND_GREEN,
		Blue	= FOREGROUND_BLUE,
		Yellow	= FOREGROUND_RED | FOREGROUND_GREEN,
	}
} else {
	/*
	 * ANSI colour codes per ECMA-48 (minus 30).
	 * e.g., Yellow = 3 + 30 = 33.
	 */
	enum ConsoleColour {
		Black	= 0,
		Red		= 1,
		Green	= 2,
		Yellow	= 3,
		Blue	= 4,
		Magenta	= 5,
		Cyan	= 6,
		White	= 7,
	}
}

void writeColouredText(File pipe, ConsoleColour colour, scope void delegate() dg) {
	bool coloursEnabled = true;  // XXX: Fix me!
	if(coloursEnabled) {
		version(Windows) {
			HANDLE handle;
			CONSOLE_SCREEN_BUFFER_INFO termInfo;
			
			if(pipe == stderr) {
				handle = GetStdHandle(STD_ERROR_HANDLE);
			} else {
				handle = GetStdHandle(STD_OUTPUT_HANDLE);
			}
			
			GetConsoleScreenBufferInfo(handle, &termInfo);		
			SetConsoleTextAttribute(handle, colour);
			SetConsoleTextAttribute(handle, termInfo.wAttributes);
		} else {
			static char[5] ansiSequence = [0x1B, '[', '3', '0', 'm'];
			ansiSequence[3] = cast(char)(colour + '0');
			pipe.write(ansiSequence);
			pipe.write("\x1b[0m");
		}
		
		dg();
	} else {
		dg();
	}
}

