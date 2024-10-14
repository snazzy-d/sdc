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
	const(void*)[][] worklist;

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

	void addToWorkList(const(void*)[][] ranges) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Scanner*) &this).addToWorkListImpl(ranges);
	}

	void addToWorkList(const(void*)[] range) shared {
		// The runtime might try to add empty ranges when scanning
		// globals, stack, TLS, etc...
		if (range.length > 0) {
			addToWorkList((&range)[0 .. 1]);
		}
	}

private:
	void runMark() shared {
		auto worker = Worker(&this);

		/**
		 * Scan the stack and TLS.
		 * 
		 * It may seems counter intuitive that we do so for worker threads
		 * as well,b ut it turns out to be necessary. NPTL caches resources
		 * necessary to start a thread after a thread exits, to be able to
		 * restart new ones quickly and cheaply.
		 * 
		 * Because we start and stop threads during the mark phase, we are
		 * at risk of missing pointers allocated for thread management resources
		 * and corrupting the internal of the standard C library.
		 * 
		 * This is NOT good! So we scan here to make sure we don't miss anything.
		 */
		__sd_gc_thread_scan(worker.scan);

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
		 * of active thread is 0, then we know no more work is comming
		 * and we shoudl stop.
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
		auto start = stop - 1;

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
		enum ElementSize = typeof(worklist[0]).sizeof;

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

	void addToWorkListImpl(const(void*)[][] ranges) {
		assert(mutex.isHeld(), "mutex not held!");
		assert(0 < ranges.length && ranges.length < uint.max,
		       "Invalid ranges count!");

		auto capacity = cursor + ranges.length;
		ensureWorklistCapacity(capacity);

		foreach (r; ranges) {
			assert(r.length > 0, "Cannot add empty range to the worklist!");
			worklist[cursor++] = r;
		}
	}
}

private:

struct Worker {
	enum WorkListCapacity = 16;
	enum MaxRefill = 1;

private:
	shared(Scanner)* scanner;

	uint cursor;
	const(void*)[][WorkListCapacity] worklist;

	// TODO: Use a different caching layer that
	//       can cache negative results.
	CachedExtentMap emap;

public:
	this(shared(Scanner)* scanner) {
		this.scanner = scanner;

		import d.gc.tcache;
		this.emap = threadCache.emap;
	}

	void refill(const(void*)[][] ranges) {
		assert(cursor == 0, "Refilling a worker that is not empty!");

		cursor = cast(uint) ranges.length;
		assert(cursor > 0 && cursor <= MaxRefill, "Invalid refill amount!");

		foreach (i, r; ranges) {
			worklist[i] = r;
		}
	}

	void scan() {
		if (cursor > 0) {
			scan(worklist[--cursor]);
		}

		assert(cursor == 0, "Scan left elements in the worklist!");
	}

	void scan(const(void*)[] range) {
		auto ms = scanner.managedAddressSpace;
		auto cycle = scanner.gcCycle;

		const(void*)[] lastDenseSlab;
		PageDescriptor lastDenseSlabPageDescriptor;

		import d.gc.slab;
		BinInfo lastDenseBin;

		while (true) {
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
					auto base = cast(void*) lastDenseSlab.ptr;
					auto offset = ptr - base;
					auto index = lastDenseBin.computeIndex(offset);

					auto pd = lastDenseSlabPageDescriptor;
					auto slotSize = lastDenseBin.slotSize;

					if (!markDense(base, index, pd)) {
						continue;
					}

					if (pd.containsPointers) {
						auto slotPtr = cast(void**) (base + index * slotSize);
						addToWorkList(slotPtr[0 .. slotSize / PointerSize]);
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

					auto base = cast(void**) (aptr - pd.index * PageSize);
					lastDenseSlab =
						base[0 .. lastDenseBin.npages * PointerInPage];

					goto MarkDense;
				}

				if (ec.isSlab()) {
					markSparse(pd, ptr, cycle);
				} else {
					markLarge(pd, cycle);
				}
			}

			// In case we reached our limit, we bail. This ensures that
			// we can scan iterratively.
			if (cursor == 0) {
				return;
			}

			range = worklist[--cursor];
		}
	}

private:
	bool markDense(const void* base, uint index, PageDescriptor pd) {
		auto e = pd.extent;

		/**
		 * /!\ This is not thread safe.
		 * 
		 * In the context of concurent scans, slots might be
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

	void addToWorkList(const(void*)[] range) {
		if (likely(cursor < WorkListCapacity)) {
			worklist[cursor++] = range;
			return;
		}

		// Flush the current worklist except the first element in it
		// so we do not starve this worker.
		scanner.addToWorkList(worklist[0 .. WorkListCapacity]);

		cursor = 1;
		worklist[0] = range;
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
			addToSharedWorklist(se.computeRange());
		}
	}

	void addToSharedWorklist(const(void*)[] range) {
		assert(range.length > 0, "Cannot add empty range to the worklist!");

		// Make sure we do not starve ourselves. If we do not have
		// work in advance, then just keep some of it for ourselves.
		if (cursor == 0) {
			worklist[cursor++] = range;
			return;
		}

		scanner.addToWorkList(range);
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

		// In order to expose some parallelism, we split the range
		// into smaller chunks to be distributed.
		static next(ref const(void*)[] range) {
			enum WorkUnit = 16 * PointerInPage;
			enum SplitThresold = 3 * WorkUnit / 2;

			if (range.length <= SplitThresold) {
				scope(success) range = [];
				return range;
			}

			scope(success) range = range[WorkUnit .. range.length];
			return range[0 .. WorkUnit];
		}

		// Make sure we do not starve ourselves. If we do not have
		// work in advance, then just keep some of it for ourselves.
		if (cursor == 0) {
			cursor = 1;
			worklist[0] = next(range);
		}

		while (range.length > 0) {
			uint count;
			const(void*)[][16] units;

			foreach (ref u; units) {
				if (range.length == 0) {
					break;
				}

				count++;
				u = next(range);
			}

			scanner.addToWorkList(units[0 .. count]);
		}
	}
}
