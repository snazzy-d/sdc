module sdc.terminal;

version(Windows) {
    import std.c.windows.windows;
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