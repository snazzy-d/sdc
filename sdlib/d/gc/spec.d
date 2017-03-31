module d.gc.spec;

enum LgSizeofPtr = 3;
enum SizeofPtr = 1 << LgSizeofPtr;

enum LgPageSize	= 12;
enum PageSize	= 1UL << LgPageSize;
enum PageMask	= PageSize - 1;

// A chunk is 1024 pages.
enum LgChunkPageCount	= 10;
enum ChunkPageCount		= 1UL << LgChunkPageCount;
enum LgChunkSize		= LgPageSize + LgChunkPageCount;
enum ChunkSize			= 1UL << LgChunkSize;
enum AlignMask			= ChunkSize - 1;
