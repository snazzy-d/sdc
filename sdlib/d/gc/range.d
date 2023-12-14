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

bool contains(const(void*)[] range, void* ptr) {
	const void* base = range.ptr;
	return ptr - base < range.length * PointerSize;
}

unittest contains {
	import d.gc.spec;
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
