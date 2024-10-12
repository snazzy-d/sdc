module core.stdc.stdlib;

extern(C):

// @trusted: // Types only.
// nothrow:
// @nogc:

void* malloc(size_t size);
void free(void* ptr);
void* calloc(size_t nmemb, size_t size);
void* realloc(void* ptr, size_t size);

void exit(int code);
