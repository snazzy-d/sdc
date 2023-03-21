module d.gc.extent;

import d.gc.heap;
import d.gc.rbtree;
import d.gc.sizeclass;
import d.gc.util;

alias ExtentTree = RBTree!(Extent, addrRangeExtentCmp);

alias PHNode = heap.Node!Extent;
alias RBNode = rbtree.Node!Extent;

struct Extent {
	enum Align = 128;
	enum Size = alignUp(Extent.sizeof, Align);

private:
	ulong bits;

public:
	import d.gc.arena;
	Arena* arena;

	void* addr;
	size_t size;

	import d.gc.hpd;
	HugePageDescriptor* hpd;

	// Not necesserly unique, as splitting an Extent
	// Will create two extent with the same serial.
	// size_t serialNumber;

private:
	union Links {
		PHNode phnode;
		RBNode rbnode;
	}

	Links _links;

	import d.gc.bitmap;
	Bitmap!512 _slabData;

public:
	this(Arena* arena, void* addr, size_t size) {
		this(arena, addr, size, cast(ubyte) ClassCount.Total);
	}

	this(Arena* arena, void* addr, size_t size, ubyte sizeClass) {
		this.bits = ulong(sizeClass) << 56;

		this.arena = arena;
		this.addr = addr;
		this.size = size;
	}

	@property
	ubyte sizeClass() const {
		ubyte sc = bits >> 56;

		// FIXME: out contract.
		assert(sc < ClassCount.Total);
		return sc;
	}

	@property
	ref PHNode phnode() {
		return _links.phnode;
	}

	@property
	ref RBNode rbnode() {
		return _links.rbnode;
	}

	bool isSlab() const {
		return (bits & 0x01) != 0;
	}

	@property
	ref Bitmap!512 slabData() {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		return _slabData;
	}
}

static assert(Extent.Size == Extent.Align, "Unexpected extent size!");

ptrdiff_t identityExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs;
	auto r = cast(size_t) rhs;

	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto r = cast(size_t) rhs.addr;

	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

ptrdiff_t addrRangeExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto rstart = cast(size_t) rhs.addr;
	auto rend = rstart + rhs.size;

	// We need to compare that way to avoid integer overflow.
	return (l >= rend) - (l < rstart);
}

ptrdiff_t sizeAddrExtentCmp(Extent* lhs, Extent* rhs) {
	auto rAddr = cast(size_t) rhs.addr;
	int rSizeClass = rhs.sizeClass;

	int lSizeClass;
	size_t lAddr;
	auto l = cast(size_t) lhs;

	import d.gc.spec;
	if (l & ~PageMask) {
		lAddr = cast(size_t) lhs.addr;
		lSizeClass = lhs.sizeClass;
	} else {
		lAddr = 0;
		lSizeClass = cast(int) (l & PageMask);
	}

	if (lSizeClass != rSizeClass) {
		return lSizeClass - rSizeClass;
	}

	return (lAddr > rAddr) - (lAddr < rAddr);
}
