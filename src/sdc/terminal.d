module sdc.terminal;

import std.stdio;

import sdc.location;
import sdc.compilererror;


version(Windows) {
    import std.c.windows.windows;
}

void outputCaretDiagnostics(Location loc)
{
    char[] line = readErrorLine(loc);
    stderr.writeln('\t', line);
    
    line[] = '~';
    line[loc.column - 1] = '^';
    
    writeColoredText(stderr, ConsoleColor.Yellow, {
        stderr.writeln('\t', line);
    });
}

version(Windows) {
    enum ConsoleColor : WORD
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
    enum ConsoleColor
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

void writeColoredText(File pipe, ConsoleColor color, scope void delegate() dg)
{
    version(Windows) {
        HANDLE handle;
        
        if(pipe == stderr) {
            handle = GetStdHandle(STD_ERROR_HANDLE);
        } else {
            handle = GetStdHandle(STD_OUTPUT_HANDLE);
        } 
        
        CONSOLE_SCREEN_BUFFER_INFO termInfo;
        GetConsoleScreenBufferInfo(handle, &termInfo);
        
        SetConsoleTextAttribute(handle, color);
    } else {
        static char[5] colorBuffer = [0x1B, '[', '3', '0', 'm'];
        colorBuffer[3] = cast(char)(color + '0');
        
        pipe.write(colorBuffer);
    }
    
    dg();
    
    version(Windows) {
        SetConsoleTextAttribute(handle, termInfo.wAttributes);
    } else {
        pipe.write("\x1b[30m");
    }
}