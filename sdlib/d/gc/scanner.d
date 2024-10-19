module d.gc.scanner;

import sdc.intrinsics;

import d.gc.emap;
import d.gc.hooks;
import d.gc.range;
import d.gc.spec;
import d.gc.util;

struct Scanner {
private:
	import d.sync.mutex;
	Mutex mutex;

	uint activeThreads;
	uint cursor;
	WorkItem[] worklist;

	ubyte _gcCycle;
	AddressRange _managedAddressSpace;

public:
	this(uint threadCount, ubyte gcCycle, AddressRange managedAddressSpace) {
		activeThreads = threadCount;

		this._gcCycle = gcCycle;
		this._managedAddressSpace = managedAddressSpace;
	}

	this(ubyte gcCycle, AddressRange managedAddressSpace) {
		import d.gc.cpu;
		auto nthreads = getCoreCount();
		assert(nthreads >= 1, "Expected at least one thread!");

		this(nthreads, gcCycle, managedAddressSpace);
	}

	@property
	AddressRange managedAddressSpace() shared {
		return (cast(Scanner*) &this)._managedAddressSpace;
	}

	@property
	ubyte gcCycle() shared {
		return (cast(Scanner*) &this)._gcCycle;
	}

	void mark() shared {
		import core.stdc.pthread;
		auto threadCount = activeThreads - 1;
		auto threadsPtr =
			cast(pthread_t*) alloca(pthread_t.sizeof * threadCount);
		auto threads = threadsPtr[0 .. threadCount];

		static void* markThreadEntry(void* ctx) {
			import d.gc.tcache;
			threadCache.activateGC(false);

			(cast(shared(Scanner*)) ctx).runMark();
			return null;
		}

		// First thing, start the worker threads, so they can do work ASAP.
		foreach (ref tid; threads) {
			pthread_create(&tid, null, markThreadEntry, cast(void*) &this);
		}

		// Scan the roots.
		__sd_gc_global_scan(addToWorkList);

		// Now send this thread marking!
		runMark();

		// We now done, we can free the worklist.
		import d.gc.tcache;
		threadCache.free(cast(void*) worklist.ptr);

		foreach (tid; threads) {
			void* ret;
			pthread_join(tid, &ret);
		}
	}

	void addToWorkList(WorkItem[] items) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Scanner*) &this).addToWorkListImpl(items);
	}

	void addToWorkList(WorkItem item) shared {
		addToWorkList((&item)[0 .. 1]);
	}

	void addToWorkList(const(void*)[] range) shared {
		// In order to expose some parallelism, we split the range
		// into smaller chunks to be distributed.
		while (range.length > 0) {
			uint count;
			WorkItem[16] units;

			foreach (ref u; units) {
				if (range.length == 0) {
					break;
				}

				count++;
				u = WorkItem.extractFromRange(range);
			}

			addToWorkList(units[0 .. count]);
		}
	}

private:
	void runMark() shared {
		auto worker = Worker(&this);

		/**
		 * Scan the stack and TLS.
		 * 
		 * It may seems counter intuitive that we do so for worker threads
		 * as well, but it turns out to be necessary. NPTL caches resources
		 * necessary to start a thread after a thread exits, to be able to
		 * restart new ones quickly and cheaply.
		 * 
		 * Because we start and stop threads during the mark phase, we are
		 * at risk of missing pointers allocated for thread management resources
		 * and corrupting the internal of the standard C library.
		 * 
		 * This is NOT good! So we scan here to make sure we don't miss anything.
		 */
		import d.gc.thread;
		threadScan(worker.scan);

		while (waitForWork(worker)) {
			worker.scan();
		}
	}

	bool waitForWork(ref Worker worker) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		activeThreads--;

		/**
		 * We wait for work to be present in the worklist.
		 * If there is, then we pick it up and start marking.
		 *
		 * Alternatively, if there is no work to do, and the number
		 * of active thread is 0, then we know no more work is coming
		 * and we should stop.
		 */
		static hasWork(Scanner* w) {
			return w.cursor != 0 || w.activeThreads == 0;
		}

		auto w = (cast(Scanner*) &this);
		mutex.waitFor(w.hasWork);

		if (w.cursor == 0) {
			return false;
		}

		activeThreads++;

		auto stop = w.cursor;
		auto start = stop;

		uint length = 0;
		foreach (_; 0 .. Worker.MaxRefill) {
			length += w.worklist[--start].length;

			enum RefillTargetSize = PageSize;
			if (start == 0 || length >= RefillTargetSize) {
				break;
			}
		}

		w.cursor = start;
		worker.refill(w.worklist[start .. stop]);

		return true;
	}

	void ensureWorklistCapacity(size_t count) {
		assert(mutex.isHeld(), "mutex not held!");
		assert(count < uint.max, "Cannot reserve this much capacity!");

		if (likely(count <= worklist.length)) {
			return;
		}

		enum MinWorklistSize = 4 * PageSize;

		auto size = count * WorkItem.sizeof;
		if (size < MinWorklistSize) {
			size = MinWorklistSize;
		} else {
			import d.gc.sizeclass;
			size = getAllocSize(count * WorkItem.sizeof);
		}

		import d.gc.tcache;
		auto ptr = threadCache.realloc(worklist.ptr, size, false);
		worklist = (cast(WorkItem*) ptr)[0 .. size / WorkItem.sizeof];
	}

	void addToWorkListImpl(WorkItem[] items) {
		assert(mutex.isHeld(), "mutex not held!");
		assert(0 < items.length && items.length < uint.max,
		       "Invalid item count!");

		auto capacity = cursor + items.length;
		ensureWorklistCapacity(capacity);

		foreach (item; items) {
			worklist[cursor++] = item;
		}
	}
}

private:

struct Worker {
	enum WorkListCapacity = 16;
	enum MaxRefill = 4;

private:
	shared(Scanner)* scanner;

	uint cursor;
	WorkItem[WorkListCapacity] worklist;

	// TODO: Use a different caching layer that
	//       can cache negative results.
	CachedExtentMap emap;

public:
	this(shared(Scanner)* scanner) {
		this.scanner = scanner;

		import d.gc.tcache;
		this.emap = threadCache.emap;
	}

	void refill(WorkItem[] items) {
		assert(cursor == 0, "Refilling a worker that is not empty!");

		cursor = cast(uint) items.length;
		assert(cursor > 0 && cursor <= MaxRefill, "Invalid refill amount!");

		foreach (i, item; items) {
			worklist[i] = item;
		}
	}

	void scan() {
		if (cursor > 0) {
			scan(worklist[--cursor]);
		}

		assert(cursor == 0, "Scan left elements in the worklist!");
	}

	void scan(const(void*)[] range) {
		while (range.length > 0) {
			scan(WorkItem.extractFromRange(range));
		}
	}

	void scan(WorkItem item) {
		auto ms = scanner.managedAddressSpace;
		auto cycle = scanner.gcCycle;

		AddressRange lastDenseSlab;
		PageDescriptor lastDenseSlabPageDescriptor;

		import d.gc.slab;
		BinInfo lastDenseBin;

		while (true) {
			auto range = item.range;
			auto current = range.ptr;
			auto top = current + range.length;

			for (; current < top; current++) {
				auto ptr = *current;
				if (!ms.contains(ptr)) {
					// This is not a pointer, move along.
					continue;
				}

				if (lastDenseSlab.contains(ptr)) {
				MarkDense:
					auto base = lastDenseSlab.ptr;
					auto offset = ptr - base;
					auto index = lastDenseBin.computeIndex(offset);

					auto pd = lastDenseSlabPageDescriptor;
					auto slotSize = lastDenseBin.slotSize;

					if (!markDense(base, index, pd)) {
						continue;
					}

					if (pd.containsPointers) {
						auto item = WorkItem(base + index * slotSize, slotSize);
						addToWorkList(item);
					}

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

					lastDenseSlab =
						AddressRange(aptr - pd.index * PageSize,
						             lastDenseBin.npages * PointerInPage);

					goto MarkDense;
				}

				if (ec.isSlab()) {
					markSparse(pd, ptr, cycle);
				} else {
					markLarge(pd, cycle);
				}
			}

			// In case we reached our limit, we bail. This ensures that
			// we can scan iteratively.
			if (cursor == 0) {
				return;
			}

			item = worklist[--cursor];
		}
	}

private:
	bool markDense(const void* base, uint index, PageDescriptor pd) {
		auto e = pd.extent;

		/**
		 * /!\ This is not thread safe.
		 * 
		 * In the context of concurrent scans, slots might be
		 * allocated/deallocated from the slab while we scan.
		 * It is unclear how to handle this at this time.
		 */
		if (!e.slabData.valueAt(index)) {
			return false;
		}

		auto ec = pd.extentClass;
		if (ec.supportsInlineMarking) {
			if (e.slabMetadataMarks.setBitAtomic(index)) {
				return false;
			}
		} else {
			auto bmp = &e.outlineMarks;
			if (bmp is null || bmp.setBitAtomic(index)) {
				return false;
			}
		}

		return true;
	}

	void addToWorkList(WorkItem item) {
		if (likely(cursor < WorkListCapacity)) {
			worklist[cursor++] = item;
			return;
		}

		// Flush the current worklist and add the item.
		scanner.addToWorkList(worklist[0 .. WorkListCapacity]);

		cursor = 1;
		worklist[0] = item;
	}

	void markSparse(PageDescriptor pd, const void* ptr, ubyte cycle) {
		import d.gc.slab;
		auto se = SlabEntry(pd, ptr);
		auto bit = 0x100 << se.index;

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
			auto r = se.computeRange();
			addToSharedWorklist(WorkItem(r));
		}
	}

	void addToSharedWorklist(WorkItem item) {
		// Make sure we do not starve ourselves. If we do not have
		// work in advance, then just keep some of it for ourselves.
		if (cursor == 0) {
			worklist[cursor++] = item;
		} else {
			scanner.addToWorkList(item);
		}
	}

	void markLarge(PageDescriptor pd, ubyte cycle) {
		auto e = pd.extent;
		auto old = e.gcWord.load();
		while (true) {
			if (old == cycle) {
				return;
			}

			if (e.gcWord.casWeak(old, cycle)) {
				break;
			}
		}

		if (pd.containsPointers && e.usedCapacity >= PointerSize) {
			splitAndAddToWorklist(
				makeRange(e.address, e.address + e.usedCapacity));
		}
	}

	void splitAndAddToWorklist(const(void*)[] range) {
		assert(isAligned(range.ptr, PageSize),
		       "Range is not aligned properly!");
		assert(range.length > 0, "Cannot add empty range to the worklist!");

		// Make sure we do not starve ourselves. If we do not have
		// work in advance, then just keep some of it for ourselves.
		if (cursor == 0) {
			worklist[cursor++] = WorkItem.extractFromRange(range);
		}

		scanner.addToWorkList(range);
	}
}

struct WorkItem {
private:
	size_t payload;

	// Verify our assumptions.
	static assert(LgAddressSpace <= 48, "Address space too large!");

	// Useful constants for bit manipulations.
	enum LengthShift = 48;
	enum FreeBits = 8 * PointerSize - LengthShift;

public:
	@property
	void* ptr() {
		return cast(void*) (payload & AddressMask);
	}

	@property
	size_t length() {
		auto ptrlen = 1 + (payload >> LengthShift);
		return ptrlen * PointerSize;
	}

	@property
	const(void*)[] range() {
		auto base = cast(void**) ptr;
		return base[0 .. length / PointerSize];
	}

	this(const void* ptr, size_t length) {
		assert(isAligned(ptr, PointerSize), "Invalid ptr!");

		auto storedLength = length / PointerSize - 1;
		assert(storedLength < (1 << FreeBits), "Invalid length!");

		payload = cast(size_t) ptr;
		payload |= storedLength << LengthShift;
	}

	this(const(void*)[] range) {
		assert(range.length > 0, "WorkItem cannot be empty!");

		payload = cast(size_t) range.ptr;
		payload |= (range.length - 1) << LengthShift;
	}

	static extractFromRange(ref const(void*)[] range) {
		assert(range.length > 0, "range cannot be empty!");

		enum WorkUnit = 16 * PointerInPage;
		enum SplitThresold = 3 * WorkUnit / 2;

		// We use this split strategy as it guarantee that any straggler
		// work item will be between 1/2 and 3/2 work unit.
		if (range.length <= SplitThresold) {
			scope(success) range = [];
			return WorkItem(range);
		}

		scope(success) range = range[WorkUnit .. range.length];
		return WorkItem(range[0 .. WorkUnit]);
	}
}

unittest WorkItem {
	void* stackPtr;
	void* ptr = &stackPtr;

	foreach (i; 0 .. 1 << WorkItem.FreeBits) {
		auto n = i + 1;

		foreach (k; 0 .. PointerSize) {
			auto item = WorkItem(ptr, n * PointerSize + k);
			assert(item.ptr is ptr);
			assert(item.length == n * PointerSize);

			auto range = item.range;
			assert(range.ptr is cast(const(void*)*) ptr);
			assert(range.length == n);

			auto ir = WorkItem(range);
			assert(item.payload == ir.payload);
		}
	}
}
