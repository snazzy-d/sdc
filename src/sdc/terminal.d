/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */ 
module sdc.terminal;

import std.stdio;

import sdc.location;
import sdc.compilererror;

import sdc.global;


version(Windows) {
    import std.c.windows.windows;
}

void outputCaretDiagnostics(Location loc, string fixHint)
{
    char[] line = readErrorLine(loc);
    if (loc.length == -1) {
        loc.length = line.length - loc.column;
    }
    
    while(line.length > 0 && (line[0] == ' ' || line[0] == '\t')) {
        line = line[1..$];
        
        if(loc.column > 0) {
            loc.column--;
        }
    }
    
    writeColouredText(stderr, ConsoleColour.Green, {
        stderr.writeln('\t', line);
    });
    
    if(loc.column == Location.wholeLine) {
        line[] = '~';
    } else {
        if(loc.column + loc.length > line.length) {
            line.length = loc.column + loc.length;
        }
        
        line[] = ' ';
        line[loc.column - 1] = '^';
        foreach(i; loc.column .. loc.column + loc.length - 1) {
            line[i] = '~';
        }
    }
    
    writeColouredText(stderr, ConsoleColour.Yellow, {
        stderr.writeln('\t', line);
    });
    
    if(fixHint !is null) {
        line[] = ' ';
        writeColouredText(stderr, ConsoleColour.Yellow, {
            stderr.writeln('\t', line[0 .. loc.column - 1], fixHint);
        });
    }
}

version(Windows) {
    enum ConsoleColour : WORD
    {
        Red = FOREGROUND_RED,
        Green = FOREGROUND_GREEN,
        Blue = FOREGROUND_BLUE,
        Yellow = FOREGROUND_RED | FOREGROUND_GREEN
    }
} else {
    /*
     * ANSI colour codes per ECMA-48 (minus 30).
     * e.g., Yellow = 3 + 30 = 33.
     */
    enum ConsoleColour
    {
        Black = 0,
        Red = 1,
        Green = 2,
        Yellow = 3,
        Blue = 4,
        Magenta = 5,
        Cyan = 6,
        White = 7
    }
}

void writeColouredText(File pipe, ConsoleColour colour, scope void delegate() dg)
{
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
