module sdcruntime.gc;

void* gcMalloc(size_t n)
{
    return GC_malloc(n);
}
