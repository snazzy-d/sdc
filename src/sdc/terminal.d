module sdc.terminal;

import std.stdio;

import sdc.location;
import sdc.compilererror;


version(Windows) {
    import std.c.windows.windows;
} else {
    // import POSIX stuff
}

void outputCaretDiagnostics(Location loc)
{
    char[] line = readErrorLine(loc);
    stderr.writeln('\t', line);
    
    line[] = '~';
    line[loc.column - 1] = '^';
    
    writeColoredText({
        stderr.writeln('\t', line);
    });
}

// putting color selection off until ANSI terminal implementation
void writeColoredText(scope void delegate() dg)
{
    version(Windows) {
        CONSOLE_SCREEN_BUFFER_INFO termInfo;
        
        GetConsoleScreenBufferInfo(
            GetStdHandle(STD_ERROR_HANDLE),
            &termInfo
        );
        
        SetConsoleTextAttribute(
            GetStdHandle(STD_ERROR_HANDLE),
            FOREGROUND_RED | FOREGROUND_GREEN
        );
    }
    
    dg();
    
    version(Windows)
    {
        SetConsoleTextAttribute(
            GetStdHandle(STD_ERROR_HANDLE),
            termInfo.wAttributes
        );
    }
}