module core.stdc.unistd;

// POSIX.1 (1996)
enum STDIN_FILENO = 0;
enum STDOUT_FILENO = 1;
enum STDERR_FILENO = 2;

extern(C):

// @trusted: // Types only.
// nothrow:
// @nogc:

int write(int fd, const char* buf, int count);
