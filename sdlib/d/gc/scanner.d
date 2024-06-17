module d.gc.scanner;

import sdc.intrinsics;

import d.gc.emap;
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
	const(void*)[] _managedAddressSpace;

public:
	this(uint threadCount, ubyte gcCycle, const(void*)[] managedAddressSpace) {
		activeThreads = threadCount;

		this._gcCycle = gcCycle;
		this._managedAddressSpace = managedAddressSpace;
	}

	this(ubyte gcCycle, const(void*)[] managedAddressSpace) {
		import sys.linux.sysinfo;
		auto nthreads = get_nprocs();
		assert(nthreads >= 1, "Expected at least one thread!");

		this(nthreads, gcCycle, managedAddressSpace);
	}

	@property
	const(void*)[] managedAddressSpace() shared {
		return (cast(Scanner*) &this)._managedAddressSpace;
	}

	@property
	ubyte gcCycle() shared {
		return (cast(Scanner*) &this)._gcCycle;
	}

	void mark() shared {
		import core.stdc.pthread;
		auto threadCount = activeThreads - 1;
		auto size = pthread_t.sizeof * threadCount;

		import d.gc.tcache;
		auto threadsPtr =
			cast(pthread_t*) threadCache.alloc(size, false, false);
		auto threads = threadsPtr[0 .. threadCount];

		static void* markThreadEntry(void* ctx) {
			auto scanner = cast(shared(Scanner*)) ctx;
			auto worker = Worker(scanner);

			// Scan the registered TLS segments.
			import d.gc.tcache;
			foreach (s; threadCache.tlsSegments) {
				worker.scan(s);
			}

		import d.gc.tcache;
		auto threadsPtr =
			cast(pthread_t*) threadCache.alloc(size, false, false);
		auto threads = threadsPtr[0 .. threadCount];

		static void* markThreadEntry(void* ctx) {
			(cast(shared(Scanner*)) ctx).runMark();
			return null;
		}

		// First thing, start the worker threads, so they can do work ASAP.
		foreach (ref tid; threads) {
			pthread_create(&tid, null, markThreadEntry, cast(void*) &this);
		}

		// Scan the roots.
		import d.thread;
		__sd_global_scan(addToWorkList);

		// Now send this thread marking!
		runMark();

		// We now done, we can free the worklist.
		threadCache.free(cast(void*) worklist.ptr);

		foreach (tid; threads) {
			void* ret;
			pthread_join(tid, &ret);
		}

		threadCache.free(threadsPtr);
	}

	void addToWorkList(const(void*)[] range) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Scanner*) &this).addToWorkListImpl(range);
	}

private:
	void runMark() shared {
		auto worker = Worker(&this);

		// Scan the stack and TLS.
		import d.thread;
		__sd_thread_scan(worker.scan);

		processWorkList(worker);
	}

	void processWorkList(ref Worker worker) shared {
		const(void*)[] range;

		while (waitForWork(range)) {
			worker.scan(range);
		}
	}

	bool waitForWork(ref const(void*)[] range) shared {
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
		range = w.worklist[--w.cursor];
		return true;
	}

	void increaseWorklistCapacity(uint count) {
		assert(mutex.isHeld(), "mutex not held!");

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

	void addToWorkListImpl(const(void*)[] range) {
		assert(mutex.isHeld(), "mutex not held!");

		auto count = cursor + 1;
		if (unlikely(count > worklist.length)) {
			increaseWorklistCapacity(count);
		}

		worklist[cursor++] = range;
	}
}

private:

struct Worker {
private:
	shared(Scanner)* scanner;

	uint cursor;
	const(void*)[][17] worklist;

	// TODO: Use a different caching layer that
	//       can cache negative results.
	CachedExtentMap emap;

public:
	this(shared(Scanner)* scanner) {
		this.scanner = scanner;

		import d.gc.tcache;
		this.emap = threadCache.emap;
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
						base[0 .. lastDenseBin.npages * PageSize / PointerSize];

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
			scanner.addToWorkList(se.computeRange());
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

		if (pd.containsPointers) {
			scanner.addToWorkList(makeRange(e.address, e.address + e.size));
		}
	}

	void addToWorkList(const(void*)[] range) {
		if (likely(cursor < worklist.length)) {
			worklist[cursor++] = range;
			return;
		}

		foreach (i; 1 .. worklist.length) {
			// FIXME: Purge the worklist all at once.
			scanner.addToWorkList(worklist[i]);
		}

		cursor = 2;
		worklist[1] = range;
	}
}
