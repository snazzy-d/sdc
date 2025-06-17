module d.gc.spec;

import d.gc.util;

// Pointer sized one.
enum size_t One = 1;

// Pointer size.
enum LgPointerSize = log2floor(size_t.sizeof);
enum PointerSize = One << LgPointerSize;

static assert(PointerSize == size_t.sizeof, "Invalid pointer size!");

// We want 64-bits aligned allocations.
enum LgQuantum = 3;
enum Quantum = One << LgQuantum;
enum QuantumMask = Quantum - 1;

static assert(Quantum >= PointerSize,
              "Quantum must be at least pointer sized!");

// Cache line.
enum LgCacheLine = 6;
enum CacheLine = One << LgCacheLine;
enum CacheLineMask = CacheLine - 1;

enum uint PointerInCacheLine = CacheLine / PointerSize;

// Page size.
enum LgPageSize = 12;
enum PageSize = One << LgPageSize;
enum PageMask = PageSize - 1;

enum uint PointerInPage = PageSize / PointerSize;

// Block size.
enum LgBlockSize = 21;
enum BlockSize = One << LgBlockSize;
enum BlockMask = BlockSize - 1;

enum uint PagesInBlock = BlockSize / PageSize;

// Virtual address space.
enum LgAddressSpace = 48;
enum AddressSpace = One << LgAddressSpace;
enum AddressMask = AddressSpace - 1;

enum PagePointerMask = AddressSpace - PageSize;
enum BlockPointerMask = AddressSpace - BlockSize;

// Allocator specific config.
enum LgExtentSize = 7;
enum ExtentSize = One << LgExtentSize;
enum ExtentAlign = ExtentSize;
enum ExtentMask = AddressSpace - ExtentAlign;

enum LgArenaCount = 12;
enum ArenaCount = 1 << LgArenaCount;
enum ArenaMask = ArenaCount - 1;

// Various thresolds.
enum PurgePageThresold = 16;
enum PurgePageThresoldSize = PurgePageThresold * PageSize;

// GC-specific items
alias Finalizer = void*;
// alias Finalizer = void function(void* ptr, size_t size);
