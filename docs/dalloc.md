# Dalloc, the D memory allocator.

Dalloc is a memory allocator for D. It is meant to be usable as the main memory
allocator for D and provide top of the line performance, as well as high
adaptability to typical D use cases.

in addition to allocating, freeing and reallocating memory, dalloc has features
required for D:

- It can collect allocations which have not been explicitly freed.
- It can track which allocations contain pointers or not, which helps speedup
  garbage collection.
- It can track appendable allocations, which can be appended to without
  reallocating when conditions allow.
- It can track destructible allocations, so the GC can run destructors when
  appropriate.

But most importantly, if the user choses to free its allocations, dalloc will
not impose the cost of using a GC on the user and performs on par with high end
malloc implementations.

## C/C++ interroperability

In order to provide full C and C++ interroperability, dalloc comes with an
implementation of the C API functions used to allocate memory. Allocations made
with the C API are considered to possibly contain pointers.

## Size class

Dalloc separates allocation sizes in classes. Computing size classes in an
apropriate way is essential: if there aren't enough size classes, we are going to
see a lot of internal fragmentation - space unused within allocations.
But if we have too many, we will often be unable to reuse gaps
between allocations, creating external fragmentation.

Dalloc uses size classes of the form `[4, 5, 6, 7] * 2^n` which provides 2 bits
of precision. This strategy is similar to the one used by jemalloc, as it turns
out to be a good tradeoff in practice.

## Extent and the Extent Map

Each memory allocation is represented by an *Extent*. Each extent runs over a
number of 4kb pages. Large allocations are rounded up to the closest number of
pages.

For small allocations, we use a special kind of Extent called a *Slab*. A Slab
allocates several slots at once, and contains a bitmap indicating which slots
are allocated or not.

In order to find an extent from an address, which is required to implement
`free` and for the marking phase of a garbage collection cycle, we use the
*Extent Map*. We assume an address space of 48bits in size, and 12 of these are
adressing within a page. This leaves us with 36bits to map from an address to an
Extent.

To do so, we use a 2 level radix tree. The first level is an array of 2^18
pointers to the next level of the tree. It is initially filled with null
pointers, which means no physical memory is mapped in the address range. The
second level is an array of 2^18 page descriptors. The page descriptor contains
various information about what's in that page, including a pointer to the related
Extent if apropriate.

The Extent Map is lock-free, so multithreaded applications can employ concurrent
mark algorithms at full speed.

Example of pointer lookup in the extent map:

```
Pointer : 0x0000403fe000
Bits    : 0000 0000 0000 0000 0100 0000 0011 1111 1110 0000 0000 0000
Bits 0  : 0000 0000 0000 0000 01
Bits 1  :                       00 0000 0011 1111 1110
Level 0 : 0x00001
Level 1 : 0x003fe 

            0       1                 3fffe   3ffff
        +-------+-------+--  ...  --+-------+-------+
        |       |       |           |       |       |
        |       |       |           |       |       |
        |       |       |           |       |       |
        +-------+---o---+--  ...  --+-------+-------+
                    |
  +-----------------+
  |
  |       0                  3fe                3ffff
  |   +-------+--  ...  --+-------+--  ...  --+-------+
  |   |       |           |       |           |       |
  +-->|       |           |       |           |       |
      |       |           |       |           |       |
      +-------+--  ...  --+-------+--  ...  --+-------+
                         /         \
      Page descriptor:  /           \
    +-------------------------------------------+
    |               :                   :       |
    | Index, Arena  :  Extent address   : Class |
    |               :                   :       |
    +-------------------------o-----------------+
                              |
  +---------------------------+
  |
  |     Extent:
  |   +-------------------------------------------+
  |   |                     :                     |
  +-->|  Extent data        :     Slab bitmap     |
      |                     :                     |
      +-------------------------------------------+
```

## Region allocator

At the root of dalloc lies the *Region Allocator*. The Region Allocator
requests and tracks ranges of address space from the OS.

It requests region of memory from the system by chunks of 1GB or more for
allocations larger than 1GB. The address space is never returned to the OS, but
the memory itself can be.

Two Region Allocators are in use: one to track regions that may contain pointers,
and one for regions that may not. This ensures that we can easily identify the
address space used for data that contains pointers, and leverage the MMU to do
write barriers, for instance.

## Arenas

Dalloc comes with 4096 pre allocated *Arenas*. Because they are all
zero-initialized, they do not take any memory in practice unless they are used.
Half of the arenas are for allocations that may contain pointers and the other half
for allocations that may not.

Arenas will request blocks (2MB) from the region allocator and allocate ranges
of 4kb pages from them. Each block used by the arena comes with a page
descriptor which has a bitmap of which pages are allocated within it or not.

The id of the CPU core on which the thread is currently running decides what
arena to use. This ensures a low level of contention in practice, and will limit
the number of arenas used to twice the number of cores on the machine.

### Large allocations

All the block descriptors which have any slots left are kept in the series of
pairing heaps, based on the maximum size class that can be allocated. The
pairing heaps allows for amortized constant time insertions and deletions. This
way, finding a block from which to allocate can be extremely quick.

### Small allocations

For each small size class, the arena contains a bin from which small allocations
can be done. Each bin contains a pairing heap of all the non-full Slabs of that
size class that the arena handles. In case a bin runs out of Slabs, a new Slab is
allocated using the same strategy as large allocations.

## Thread Cache

**/!\ Thread caches are not fully implemented as this time!**

Each thread that allocates memory has a *Thread Local Cache*. Small allocations
are typically served from the cache, and the cache is refilled in bulk from the
arena when it runs out. When freeing elements, they are not actually freed, but
instead put in the thread cache for later reuse. Elements are released in batch
when the cache grows too large.

This mechnism ensures that most of allocations avoid any possible contention and
are served as fast as possible. In addition, this improves the locality of
allocation on a per thread basis as they come from the same batch of
allocations, which reduces pressure on the TLB.
