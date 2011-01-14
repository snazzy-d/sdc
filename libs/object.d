module object;

version (D_LP64) {
    alias ulong size_t;
} else {
    alias uint  size_t;
}

