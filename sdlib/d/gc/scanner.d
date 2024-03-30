module d.gc.scanner;

import sdc.intrinsics;

import d.gc.emap;
import d.gc.range;
import d.gc.spec;
import d.gc.util;

struct Scanner {
private:
	ubyte gcCycle;
	uint cursor;

	const(void*)[] managedAddressSpace;
	const(void*)[][] worklist;

	// TODO: Use a different caching layer that
	//       can cache negative results.
	CachedExtentMap emap;

public:
	this(ubyte gcCycle, const(void*)[] managedAddressSpace,
	     ref CachedExtentMap emap) {
		this.gcCycle = gcCycle;
		this.managedAddressSpace = managedAddressSpace;
		this.emap = emap;
	}

	void scan(const(void*)[] range) {
		auto ms = managedAddressSpace;

		foreach (ptr; range) {
			if (!ms.contains(ptr)) {
				// This is not a pointer, move along.
				continue;
			}

			auto aptr = alignDown(ptr, PageSize);
			auto pd = emap.lookup(aptr);

			auto e = pd.extent;
			if (e is null) {
				// We have no mapping there, move on.
				continue;
			}

			auto ec = pd.extentClass;
			if (ec.isLarge()) {
				markLarge(pd);
			}
		}
	}

	void mark() {
		while (worklist.length > 0) {
			auto w = worklist;
			auto i = cursor;

			worklist = [];
			cursor = 0;

			while (i-- > 0) {
				scan(w[i]);
			}

			import d.gc.tcache;
			threadCache.free(w.ptr);
		}
	}

private:
	void markLarge(PageDescriptor pd) {
		auto e = pd.extent;
		auto cycle = gcCycle;

		auto old = e.gcWord.load();
		while (true) {
			if (old == cycle) {
				return;
			}

			if (e.gcWord.casWeak(old, cycle)) {
				break;
			}
		}

		if (pd.containsPointers) {
			addToWorkList(makeRange(e.address, e.address + e.size));
		}
	}

	void ensureWorklistCapacity(uint extras) {
		auto count = cursor + extras;
		if (likely(count <= worklist.length)) {
			return;
		}

		enum ElementSize = typeof(worklist[0]).sizeof;
		enum MinWorklistSize = 4 * PageSize;

		auto size = count * ElementSize;
		if (size < MinWorklistSize) {
			size = MinWorklistSize;
		} else {
			import d.gc.sizeclass;
			size = getAllocSize(count * ElementSize);
		}

		import d.gc.tcache;
		auto ptr = threadCache.realloc(worklist.ptr, size, false);
		worklist = (cast(const(void*)[]*) ptr)[0 .. size / ElementSize];
	}

	void addToWorkList(const(void*)[] range) {
		ensureWorklistCapacity(1);
		worklist[cursor++] = range;
	}
}
