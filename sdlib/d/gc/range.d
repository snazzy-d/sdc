module d.gc.range;

import d.gc.util;
import d.gc.spec;

/**
 * This function get a void[] range and chnage it into a
 * const(void*)[] one, reducing to alignement boundaries.
 */
const(void*)[] makeRange(const void[] range) {
	auto begin = alignUp(range.ptr, PointerSize);
	auto end = alignDown(range.ptr + range.length, PointerSize);

	auto ibegin = cast(size_t) begin;
	auto iend = cast(size_t) end;
	if (ibegin >= iend) {
		return [];
	}

	auto ptr = cast(void**) begin;
	auto length = (iend - ibegin) / PointerSize;

	return ptr[0 .. length];
}

const(void*)[] makeRange(const void* start, const void* stop) {
	auto length = stop - start;
	return makeRange(start[0 .. length]);
}

unittest makeRange {
	auto ptr = cast(void*) 0x56789abcd000;

	static checkEmpty(const(void*)[] r) {
		assert(r.length == 0);
	}

	static checkBounds(const(void*)[] r, void* start, void* stop) {
		assert(r.ptr is cast(const(void*)*) start);
		assert(r.ptr + r.length is cast(const(void*)*) stop);
	}

	foreach (start; 0 .. 16) {
		foreach (stop; 0 .. 16) {
			auto r0 = makeRange(ptr + start, ptr + stop);
			auto r1 = makeRange(ptr[start .. max(start, stop)]);

			auto eStart = ptr + alignUp(start, PointerSize);
			auto eStop = ptr + alignDown(stop, PointerSize);

			if (eStart >= eStop) {
				checkEmpty(r0);
				checkEmpty(r1);
			} else {
				checkBounds(r0, eStart, eStop);
				checkBounds(r1, eStart, eStop);
			}
		}
	}
}

bool contains(const(void*)[] range, const void* ptr) {
	const void* base = range.ptr;
	return ptr - base < range.length * PointerSize;
}

unittest contains {
	auto r = makeRange(cast(void*) AddressSpace, null);

	assert(!r.contains(null));
	assert(!r.contains(cast(void*) 1));
	assert(!r.contains(cast(void*) AddressSpace - 1));
	assert(!r.contains(cast(void*) AddressSpace));

	r = makeRange(cast(void*) 123, cast(void*) 456);
	assert(!r.contains(cast(void*) 122));
	assert(!r.contains(cast(void*) 123));
	assert(!r.contains(cast(void*) 127));
	assert(r.contains(cast(void*) 128));
	assert(r.contains(cast(void*) 129));
	assert(r.contains(cast(void*) 234));
	assert(r.contains(cast(void*) 345));
	assert(r.contains(cast(void*) 455));
	assert(!r.contains(cast(void*) 456));
}

const(void*)[] merge(const(void*)[] a, const(void*)[] b) {
	if (a.length == 0) {
		return b;
	}

	if (b.length == 0) {
		return a;
	}

	auto astart = a.ptr;
	auto astop = astart + a.length;

	auto bstart = b.ptr;
	auto bstop = bstart + b.length;

	import d.gc.util;
	return makeRange(min(astart, bstart), max(astop, bstop));
}

unittest merge {
	static void checkMergeImpl(const(void*)[] a, const(void*)[] b,
	                           const(void*)[] expected) {
		auto m = merge(a, b);
		assert(m.ptr is expected.ptr);
		assert(m.length == expected.length);
	}

	static void checkMergeCommutative(const(void*)[] a, const(void*)[] b,
	                                  const(void*)[] expected) {
		checkMergeImpl(a, b, expected);
		checkMergeImpl(b, a, expected);
	}

	static void checkMerge(const(void*)[] a, const(void*)[] b,
	                       const(void*)[] expected) {
		checkMergeCommutative(a, b, expected);
		checkMergeCommutative(a, expected, expected);
		checkMergeCommutative(b, expected, expected);

		checkMergeCommutative(a, a, a);
		checkMergeCommutative(b, b, b);

		auto rnull = makeRange(cast(void*) AddressSpace, null);
		checkMergeCommutative(a, rnull, a);
		checkMergeCommutative(b, rnull, b);

		auto rall = makeRange(null, cast(void*) AddressSpace);
		checkMergeCommutative(a, rall, rall);
		checkMergeCommutative(b, rall, rall);
	}

	auto rnull = makeRange(cast(void*) AddressSpace, null);
	auto rall = makeRange(null, cast(void*) AddressSpace);
	checkMerge(rnull, rall, rall);

	auto r1 = makeRange(cast(void*) 4000, cast(void*) 4080);
	auto r2 = makeRange(cast(void*) 4160, cast(void*) 4240);
	auto r3 = makeRange(cast(void*) 4100, cast(void*) 4200);

	// Disjoint ranges.
	auto r12 = makeRange(cast(void*) 4000, cast(void*) 4240);
	checkMerge(r1, r2, r12);

	// Overlapping ranges.
	auto r13 = makeRange(cast(void*) 4000, cast(void*) 4200);
	checkMerge(r1, r3, r13);

	auto r23 = makeRange(cast(void*) 4100, cast(void*) 4240);
	checkMerge(r2, r3, r23);

	// Mix and match ranges.
	checkMerge(r1, r23, r12);
	checkMerge(r2, r13, r12);
	checkMerge(r3, r12, r12);
}

/**
 * This describes a range of addresses.
 * 
 * In order to avoid false pointer, we stored the
 * complement of the base address of the range.
 */
struct AddressRange {
private:
	size_t base;
	size_t length;

public:
	this(const void[] range) {
		base = -(cast(size_t) range.ptr);
		length = range.length;
	}

	this(const void* start, const void* stop) {
		this(start[0 .. stop - start]);
	}

	bool contains(const void* ptr) const {
		auto iptr = cast(size_t) ptr;
		return (iptr + base) < length;
	}

	auto merge(AddressRange other) const {
		if (length == 0) {
			return other;
		}

		if (other.length == 0) {
			return this;
		}

		auto top = max(length - base, other.length - other.base);

		AddressRange ret;
		ret.base = max(base - 1, other.base - 1) + 1;
		ret.length = top + ret.base;

		return ret;
	}
}

unittest AddressRange {
	auto r = AddressRange(cast(void*) AddressSpace, null);

	assert(!r.contains(null));
	assert(!r.contains(cast(void*) 1));
	assert(!r.contains(cast(void*) AddressSpace - 1));

	assert(r.contains(cast(void*) AddressSpace));
	assert(r.contains(cast(void*) -1));

	r = AddressRange(cast(void*) 123, cast(void*) 456);

	assert(!r.contains(cast(void*) 122));
	assert(r.contains(cast(void*) 123));
	assert(r.contains(cast(void*) 234));
	assert(r.contains(cast(void*) 345));
	assert(r.contains(cast(void*) 455));
	assert(!r.contains(cast(void*) 456));

	static
	void checkMergeImpl(AddressRange a, AddressRange b, AddressRange expected) {
		auto m = a.merge(b);

		assert(m.base == expected.base);
		assert(m.length == expected.length);
	}

	static void checkMergeCommutative(AddressRange a, AddressRange b,
	                                  AddressRange expected) {
		checkMergeImpl(a, b, expected);
		checkMergeImpl(b, a, expected);
	}

	static
	void checkMerge(AddressRange a, AddressRange b, AddressRange expected) {
		checkMergeCommutative(a, b, expected);
		checkMergeCommutative(a, expected, expected);
		checkMergeCommutative(b, expected, expected);

		checkMergeCommutative(a, a, a);
		checkMergeCommutative(b, b, b);

		auto rnull = AddressRange(null, null);
		checkMergeCommutative(a, rnull, a);
		checkMergeCommutative(b, rnull, b);

		auto rall = AddressRange(null, cast(void*) AddressSpace);
		checkMergeCommutative(a, rall, rall);
		checkMergeCommutative(b, rall, rall);
	}

	auto rnull = AddressRange(null, null);
	auto rall = AddressRange(null, cast(void*) AddressSpace);
	checkMerge(rnull, rall, rall);

	auto r1 = AddressRange(cast(void*) 4000, cast(void*) 4080);
	auto r2 = AddressRange(cast(void*) 4160, cast(void*) 4240);
	auto r3 = AddressRange(cast(void*) 4100, cast(void*) 4200);

	// Disjoint ranges.
	auto r12 = AddressRange(cast(void*) 4000, cast(void*) 4240);
	checkMerge(r1, r2, r12);

	// Overlapping ranges.
	auto r13 = AddressRange(cast(void*) 4000, cast(void*) 4200);
	checkMerge(r1, r3, r13);

	auto r23 = AddressRange(cast(void*) 4100, cast(void*) 4240);
	checkMerge(r2, r3, r23);

	// Mix and match ranges.
	checkMerge(r1, r23, r12);
	checkMerge(r2, r13, r12);
	checkMerge(r3, r12, r12);
}
