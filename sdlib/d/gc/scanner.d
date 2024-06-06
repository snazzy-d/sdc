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

	void scanLoop(const(void*)[] range, size_t limit) {
		size_t scanned = 0;
		auto ms = managedAddressSpace;

		const(void*)[] lastDenseSlab;
		PageDescriptor lastDenseSlabPageDescriptor;

		import d.gc.slab;
		BinInfo lastDenseBin;

		while (true) {
			auto current = range.ptr;
			auto top = current + range.length;

			scanned += range.length * PointerSize;

			for (; current < top; current++) {
				auto ptr = *current;
				if (!ms.contains(ptr)) {
					// This is not a pointer, move along.
					continue;
				}

				if (lastDenseSlab.contains(ptr)) {
				MarkDense:
					auto base = cast(void*) lastDenseSlab.ptr;
					auto offset = ptr - base;
					auto index = lastDenseBin.computeIndex(offset);

					auto pd = lastDenseSlabPageDescriptor;
					auto slotSize = lastDenseBin.slotSize;

					markDense(base, index, pd, slotSize);
					continue;
				}

				auto aptr = alignDown(ptr, PageSize);
				auto pd = emap.lookup(aptr);

				auto e = pd.extent;
				if (e is null) {
					// We have no mapping here, move on.
					continue;
				}

				auto ec = pd.extentClass;
				if (ec.dense) {
					lastDenseSlabPageDescriptor = pd;
					lastDenseBin = binInfos[ec.sizeClass];

					auto base = cast(void**) (aptr - pd.index * PageSize);
					lastDenseSlab =
						base[0 .. lastDenseBin.npages * PageSize / PointerSize];

					goto MarkDense;
				}

				if (ec.isSlab()) {
					markSparse(pd, ptr);
				} else {
					markLarge(pd);
				}
			}

			// In case we reached our limit, we bail. This ensures that
			// we can scan iterratively.
			if (cursor == 0 || scanned > limit) {
				return;
			}

			range = worklist[--cursor];
		}
	}

	void scan(const(void*)[] range) {
		scanLoop(range, 16 * PageSize);
	}

	void mark() {
		scanLoop([], size_t.max);

		import d.gc.tcache;
		threadCache.free(worklist.ptr);

		worklist = [];
		cursor = 0;
	}

private:
	void markDense(const void* base, uint index, PageDescriptor pd,
	               uint slotSize) {
		auto e = pd.extent;

		/**
		 * /!\ This is not thread safe.
		 * 
		 * In the context of concurent scans, slots might be
		 * allocated/deallocated from the slab while we scan.
		 * It is unclear how to handle this at this time.
		 */
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
			auto slotPtr = cast(void**) (base + index * slotSize);
			addToWorkList(slotPtr[0 .. slotSize / PointerSize]);
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

	void increaseWorklistCapacity(uint count) {
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
		auto count = cursor + 1;
		if (unlikely(count > worklist.length)) {
			increaseWorklistCapacity(count);
		}

		worklist[cursor++] = range;
	}
}
