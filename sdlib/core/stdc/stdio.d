module core.stdc.stdio;

extern(C):

// @trusted: // Types only.
// nothrow:
// @nogc:

int printf(const char* fmt, ...);
int puts(const char* s);
int snprintf(char* dest, size_t size, const char* fmt, ...);
