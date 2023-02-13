module d.gc.spec;

import d.gc.util;

// Pointer size.
enum LgPointerSize = log2floor(size_t.sizeof);
enum PointerSize = 1UL << LgPointerSize;

static assert(PointerSize == size_t.sizeof, "Invalid pointer size!");

// We want 64-bits aligned allocations.
enum LgQuantum = 3;
enum Quantum = 1UL << LgQuantum;
enum QuantumMask = Quantum - 1;

static assert(Quantum >= PointerSize,
              "Quantum must be at least pointer sized!");

// Cache line.
enum LgCacheLine = 6;
enum CacheLine = 1UL << LgCacheLine;
enum CacheLineMask = CacheLine - 1;

// Page size.
enum LgPageSize = 12;
enum PageSize = 1UL << LgPageSize;
enum PageMask = PageSize - 1;

// Huge page size.
enum LgHugePageSize = 21;
enum HugePageSize = 1UL << LgHugePageSize;
enum HugePageMask = HugePageSize - 1;

// Virtual address space.
enum LgAddressSpace = 48;
enum AddressSpace = 1UL << LgAddressSpace;
enum AddressMask = AddressSpace - 1;

// A chunk is 1024 pages.
enum LgChunkPageCount = 10;
enum ChunkPageCount = 1UL << LgChunkPageCount;
enum LgChunkSize = LgPageSize + LgChunkPageCount;
enum ChunkSize = 1UL << LgChunkSize;
enum ChunkAlignMask = ChunkSize - 1;
