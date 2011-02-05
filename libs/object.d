module object;

version (D_LP64) {
    alias ulong size_t;
    alias long  ptrdiff_t;
} else {
    alias uint  size_t;
    alias int   ptrdiff_t;
}

extern (C) {
    void* malloc(size_t);
    void* realloc(void*, size_t);
}

