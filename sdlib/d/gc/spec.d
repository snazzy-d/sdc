module d.gc.spec;

// Pointer size.
enum LgPointerSize = 8 * size_t.sizeof;
enum PointerSize = 1UL << LgPointerSize;

// Page size.
enum LgPageSize = 12;
enum PageSize = 1UL << LgPageSize;
enum PageMask = PageSize - 1;

// Virtual address space size.
enum LgAddressSpace = 48;
enum AddressSpace = 1UL << LgAddressSpace;
enum AddressMask = AddressSpace - 1;

// A chunk is 1024 pages.
enum LgChunkPageCount = 10;
enum ChunkPageCount = 1UL << LgChunkPageCount;
enum LgChunkSize = LgPageSize + LgChunkPageCount;
enum ChunkSize = 1UL << LgChunkSize;
enum ChunkAlignMask = ChunkSize - 1;
