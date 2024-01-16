module d.gc.scanner;

import sdc.intrinsics;

import d.gc.emap;
import d.gc.range;
import d.gc.spec;
import d.gc.util;

struct Scanner {
private:
	uint cursor;

	const(void*)[] managedAddressSpace;
	const(void*)[][] worklist;

	// TODO: Use a different caching layer that
	//       can cache negative results.
	CachedExtentMap emap;

public:
	this(const(void*)[] managedAddressSpace, ref CachedExtentMap emap) {
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

			// TODO: mark.
		}
	}

	void mark() {
		scope(exit) {
			import d.gc.tcache;
			threadCache.free(worklist.ptr);
			worklist = [];
		}

		while (cursor > 0) {
			scan(worklist[--cursor]);
		}
	}
}
