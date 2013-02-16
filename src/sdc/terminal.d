/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.terminal;

import std.stdio;

import d.location;
import sdc.compilererror;


version(Windows) {
	import std.c.windows.windows;
}

void outputCaretDiagnostics(const Location loc, string fixHint) {
	uint start = loc.index;
	auto content = loc.source.content;
	
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
	
	uint end = cast(uint) (loc.index + loc.length);
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
	/*
	while(line.length > 0 && (line[0] == ' ' || line[0] == '\t')) {
		line = line[1..$];
		
		if(index > 0) {
			index--;
		}
	}
	*/
	if(index + length > line.length) {
		length = index - cast(uint) line.length;
	}
	
	writeColouredText(stderr, ConsoleColour.Green, {
		stderr.writeln('\t', line);
	});
	
	char[] underline;
	underline.length = index + length;
	underline[0 .. index][] = ' ';
	underline[index] = '^';
	foreach(i; index + 1 .. index + length) {
		underline[i] = '~';
	}
	
	writeColouredText(stderr, ConsoleColour.Yellow, {
		stderr.writeln('\t', underline);
	});
	
	if(fixHint !is null) {
		writeColouredText(stderr, ConsoleColour.Yellow, {
			stderr.writeln('\t', underline[0 .. index], fixHint);
		});
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
		scope (exit) {
			version(Windows) {
				SetConsoleTextAttribute(handle, termInfo.wAttributes);
			} else {
				pipe.write("\x1b[0m");
			}
		}
		version(Windows) {
			HANDLE handle;
			
			if(pipe == stderr) {
				handle = GetStdHandle(STD_ERROR_HANDLE);
			} else {
				handle = GetStdHandle(STD_OUTPUT_HANDLE);
			}
			
			CONSOLE_SCREEN_BUFFER_INFO termInfo;
			GetConsoleScreenBufferInfo(handle, &termInfo);
			
			SetConsoleTextAttribute(handle, colour);
		} else {
			static char[5] ansiSequence = [0x1B, '[', '3', '0', 'm'];
			ansiSequence[3] = cast(char)(colour + '0');
			pipe.write(ansiSequence);
		}
		
		dg();
	} else {
		dg();
	}
}

