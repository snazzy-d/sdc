module d.gc.spec;

enum LgPageSize = 12;
enum PageSize = 1UL << LgPageSize;
enum PageMask = PageSize - 1;

// A chunk is 1024 pages.
enum LgChunkPageCount = 10;
enum ChunkPageCount = 1UL << LgChunkPageCount;
enum LgChunkSize = LgPageSize + LgChunkPageCount;
enum ChunkSize = 1UL << LgChunkSize;
enum ChunkAlignMask = ChunkSize - 1;

// 64 bits tiny, 128 bits quantum.
enum LgTiny = 3;
enum LgQuantum = 4;
