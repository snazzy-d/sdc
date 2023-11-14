module core.stdc.stdio;

enum DbgPrintBufferSize = 4096;

static char[DbgPrintBufferSize] _dbgPrintBuffer;

void printDebug() {
	dbgprint(_dbgPrintBuffer.ptr);
}

void dbgprint(char* str) {
	write(2, str, strnlen(str, DbgPrintBufferSize));
}

extern(C):

// @trusted: // Types only.
// nothrow:
// @nogc:

int printf(const char* fmt, ...);
int puts(const char* s);
int snprintf(char* dest, size_t size, const char* fmt, ...);
int write(int fd, const char* buf, int count);
int strnlen(char* str, size_t maxlen);
