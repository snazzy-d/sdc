module object;

version (D_LP64) {
    alias ulong size_t;
    alias long  ptrdiff_t;
} else {
    alias uint  size_t;
    alias int   ptrdiff_t;
}

alias char[] string;

extern (C) {
    void* malloc(size_t);
    void* realloc(void*, size_t);
	
    void exit(int code);
    int printf(char* fmt, ...);
}

class Object
{
}

extern(C) void __d_assert(bool condition, string message)
{
    if(!condition) {
        printf("assert failed\n"); // TODO: use stderr
        exit(1);
    }
}