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

	/**
	 * It is fairly common to find a number of connected
	 * allocations on the same slab. For instance, a data
	 * structure might allocate nodes that are all the same
	 * size to manage its internal state.
	 * 
	 * In order to avoid doign too many round trips in the
	 * extent map, we simply cache the last page and its
	 * corresponding page descriptor here and reuse them
	 * when apropriate.
	 * 
	 * FIXME: We would ideally have this as locals variables
	 *        in the markign code, but the current structure
	 *        of the code makes it difficult.
	 */
	void* lastPage;
	PageDescriptor lpd;

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

			auto pd = lpd;
			auto aptr = alignDown(ptr, PageSize);
			if (aptr !is lastPage) {
				pd = emap.lookup(aptr);

				auto e = pd.extent;
				if (e is null) {
					// We have no mapping here, move on.
					continue;
				}

				lastPage = aptr;
				lpd = pd;
			}

			auto ec = pd.extentClass;
			if (ec.dense) {
				markDense(pd, ptr);
			} else if (ec.isSlab()) {
				markSparse(pd, ptr);
			} else {
				markLarge(pd);
			}
		}
	}

	void mark() {
		while (cursor > 0) {
			scan(worklist[--cursor]);
		}

		import d.gc.tcache;
		threadCache.free(worklist.ptr);

		worklist = [];
		cursor = 0;
	}

private:
	void markDense(PageDescriptor pd, const void* ptr) {
		import d.gc.slab;
		auto se = SlabEntry(pd, ptr);
		auto index = se.index;

		/**
		 * /!\ This is not thread safe.
		 * 
		 * In the context of concurent scans, slots might be
		 * allocated/deallocated from the slab while we scan.
		 * It is unclear how to handle this at this time.
		 */
		auto e = pd.extent;
		if (!e.slabData.valueAt(index)) {
			return;
		}

		auto ec = pd.extentClass;
		if (ec.supportsInlineMarking) {
			if (e.slabMetadataMarks.setBitAtomic(index)) {
				return;
			}
		} else {
			auto bmp = &e.outlineMarks;
			if (bmp is null || bmp.setBitAtomic(index)) {
				return;
			}
		}

		if (pd.containsPointers) {
			addToWorkList(se.computeRange());
		}
	}

	void markSparse(PageDescriptor pd, const void* ptr) {
		import d.gc.slab;
		auto se = SlabEntry(pd, ptr);
		auto bit = 0x100 << se.index;
		auto cycle = gcCycle;

		auto e = pd.extent;
		auto old = e.gcWord.load();
		while ((old & 0xff) != cycle) {
			if (e.gcWord.casWeak(old, cycle | bit)) {
				goto Exit;
			}
		}

		if (old & bit) {
			return;
		}

		old = e.gcWord.fetchOr(bit);
		if (old & bit) {
			return;
		}

	Exit:
		if (pd.containsPointers) {
			addToWorkList(se.computeRange());
		}
	}

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
