module d.gc.scanner;

import sdc.intrinsics;

import d.gc.emap;
import d.gc.hooks;
import d.gc.mtqueue;
import d.gc.range;
import d.gc.slab;
import d.gc.spec;
import d.gc.util;

struct Scanner {
private:
	import d.sync.mutex;
	Mutex mutex;

	ubyte _gcCycle;
	AddressRange _managedAddressSpace;

	// We do not want false sharing between the mutex and
	// the work queue, so we add padding here.
	Padding!4 _pad0;

	alias WorkQueue = ConcurentQueue!WorkItem;
	WorkQueue workQueue;

	import d.sync.atomic;
	shared Atomic!uint totalThreads;
	shared Atomic!uint activeThreads;

	// We do not want false sharing with whatever comes after this
	// struct in memory here, so we add padding here.
	Padding!1 _pad1;

public:
	this(uint threadCount, ubyte gcCycle, AddressRange managedAddressSpace) {
		totalThreads.store(threadCount);
		activeThreads.store(threadCount);

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
		enum QueueSize = 4096;
		auto size = QueueSize * WorkItem.sizeof;

		import d.gc.tcache;
		auto ptr = cast(WorkItem*) threadCache.alloc(size, false, false);
		scope(exit) threadCache.free(ptr);

		(cast(Scanner*) &this).workQueue = WorkQueue(ptr[0 .. QueueSize]);

		import core.stdc.pthread;
		auto threadCount = totalThreads.load() - 1;
		auto threadsPtr =
			cast(pthread_t*) alloca(pthread_t.sizeof * threadCount);
		auto threads = threadsPtr[0 .. threadCount];

		static void* markThreadEntry(void* ctx) {
			import d.gc.tcache;
			threadCache.activateGC(false);

			auto worker = Worker(cast(shared(Scanner*)) ctx);
			worker.runMark();

			return null;
		}

		// First thing, start the worker threads, so they can do work ASAP.
		foreach (ref tid; threads) {
			import d.rt.trampoline;
			createGCThread(&tid, null, markThreadEntry, cast(void*) &this);
		}

		// We are going to use this worker with __sd_gc_global_scan
		// so the workflow in the main thread is slightly different.
		auto worker = Worker(&this);

		// Scan the roots.
		__sd_gc_global_scan(worker.processRootRange);

		// Now send this thread marking!
		worker.runMark();

		foreach (tid; threads) {
			void* ret;
			pthread_join(tid, &ret);
		}
	}

	void addToWorkQueue(WorkItem[] items,
	                    ref Overflow!WorkItem overflow) shared {
		workQueue.insert(items, overflow);

		// If some threads are starved, notify them.
		// This inherently race-y, but it always eventually
		// picks up starved threads, so this is good enough.
		if (activeThreads.load() < totalThreads.load()) {
			// FIXME: Add a notify feature to the mutex.
			mutex.lock();
			mutex.unlock();
		}
	}

	size_t popFromWorkQueue(WorkItem[] items,
	                        ref Overflow!WorkItem overflow) shared {
		return workQueue.pop(items, overflow);
	}

private:
	size_t waitForWork(ref Worker worker, WorkItem[] items) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		activeThreads.fetchSub(1);

		static struct Waiter {
			Worker* worker;
			size_t count;

			WorkItem[] items;

			this(Worker* worker, WorkItem[] items) {
				this.worker = worker;
				this.items = items;
			}

			bool hasWork() {
				// There is no more work to be done.
				if (worker.scanner.activeThreads.load() == 0) {
					return true;
				}

				count = worker.popFromWorkQueue(items);
				return count > 0;
			}
		}

		/**
		 * The fact all the waiters use a different delegate
		 * as condition (because the waiter itself is different)
		 * will cause a loop where they wake up each others as they
		 * fail their condition.
		 * 
		 * This is somewhat wasteful, but will do for now.
		 * FIXME: Actually put multiple thread to sleep if
		 *        multiple threads are starved.
		 */
		auto waiter = Waiter(&worker, items);
		mutex.waitFor(waiter.hasWork);

		if (waiter.count > 0) {
			activeThreads.fetchAdd(1);
		}

		return waiter.count;
	}
}

private:

struct LastDenseSlabCache {
	AddressRange slab;
	PageDescriptor pageDescriptor;
	BinInfo bin;

	this(AddressRange slab, PageDescriptor pageDescriptor, BinInfo bin) {
		this.slab = slab;
		this.pageDescriptor = pageDescriptor;
		this.bin = bin;
	}
}

struct Worker {
private:
	shared(Scanner)* scanner;

	// TODO: Use a different caching layer that
	//       can cache negative results.
	CachedExtentMap emap;

	/**
	 * Cold elements that benefit from being kept alive
	 * across scan calls.
	 */
	AddressRange managedAddressSpace;
	ubyte gcCycle;

	LastDenseSlabCache ldsCache;

	Overflow!WorkItem overflow;

public:
	this(shared(Scanner)* scanner) {
		this.scanner = scanner;

		import d.gc.tcache;
		this.emap = threadCache.emap;

		this.managedAddressSpace = scanner.managedAddressSpace;
		this.gcCycle = scanner.gcCycle;
	}

	size_t waitForWork(WorkItem[] items) {
		auto count = popFromWorkQueue(items);
		if (count > 0) {
			return count;
		}

		// We are starving, defer to the scanner.
		return scanner.waitForWork(this, items);
	}

	void runMark() {
		// Make sure we cleanup after ourselves when done.
		scope(exit) overflow.clear();

		/**
		 * Scan the stack and TLS.
		 * 
		 * It may seems counter intuitive that we do so for worker threads
		 * as well, but it turns out to be necessary. NPTL caches resources
		 * necessary to start a thread after a thread exits, to be able to
		 * restart new ones quickly and cheaply.
		 * 
		 * Because we start and stop threads during the mark phase, we are
		 * at risk of missing pointers allocated for thread management
		 * resources and corrupting the internal of the standard C library.
		 * 
		 * This is NOT good! So we scan here to make sure we don't miss anything.
		 */
		import d.gc.thread;
		threadScan(scan);

		enum MaxRefill = 4;
		WorkItem[MaxRefill] refill;
		while (true) {
			auto count = waitForWork(refill[0 .. MaxRefill]);
			if (count == 0) {
				// We are done, there is no more work items.
				return;
			}

			foreach (i; 0 .. count) {
				scan(refill[i]);
			}
		}
	}

	void processRootRange(const(void*)[] range) {
		/**
		 * This specialized function either adds the range to the work
		 * list, or scans directly the range, depending if the range
		 * contains the Worker `this` pointer. If the range contains
		 * the Worker `this` pointer, then we are scanning our own
		 * stack. This can only happen in cases where a custom function
		 * has decided to scan our stack, and has pushed registers
		 * (i.e. druntime). In this case, we need to scan immediately,
		 * to avoid losing the register data!
		 */
		if (range.contains(&this)) {
			scan(range);
		} else {
			// Either a TLS range, or the stack of a suspended
			// thread. Can be scanned at any time.
			addToWorkQueue(range);
		}
	}

	void addToWorkQueue(WorkItem[] items) {
		scanner.addToWorkQueue(items, overflow);
	}

	void addToWorkQueue(WorkItem item) {
		addToWorkQueue((&item)[0 .. 1]);
	}

	void addToWorkQueue(const(void*)[] range) {
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

			addToWorkQueue(units[0 .. count]);
		}
	}

	size_t popFromWorkQueue(WorkItem[] items) {
		return scanner.popFromWorkQueue(items, overflow);
	}

	void scan(const(void*)[] range) {
		while (range.length > 0) {
			scan(WorkItem.extractFromRange(range));
		}
	}

	void scan(WorkItem item) {
		scanImpl!true(item, ldsCache);
	}

	void scanBreadthFirst(WorkItem item, LastDenseSlabCache cache) {
		scanImpl!false(item, cache);
	}

	void scanImpl(bool DepthFirst)(WorkItem item, LastDenseSlabCache cache) {
		auto ms = managedAddressSpace;

		scope(success) {
			if (DepthFirst) {
				ldsCache = cache;
			}
		}

		// Depth first doesn't really need a work list,
		// but this makes sharing code easier.
		enum WorkListCapacity = DepthFirst ? 1 : 16;

		uint cursor;
		WorkItem[WorkListCapacity] worklist;

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

				if (cache.slab.contains(ptr)) {
				MarkDense:
					auto base = cache.slab.ptr;
					auto offset = ptr - base;

					auto ldb = cache.bin;
					auto index = ldb.computeIndex(offset);

					auto pd = cache.pageDescriptor;
					assert(pd.extent !is null);
					assert(pd.extent.contains(ptr));

					if (!markDense(pd, index)) {
						continue;
					}

					if (!pd.containsPointers) {
						continue;
					}

					auto slotSize = ldb.slotSize;
					auto i = WorkItem(base + index * slotSize, slotSize);
					if (DepthFirst) {
						scanBreadthFirst(i, cache);
						continue;
					}

					if (likely(cursor < WorkListCapacity)) {
						worklist[cursor++] = i;
						continue;
					}

					addToWorkQueue(worklist[0 .. WorkListCapacity]);

					cursor = 1;
					worklist[0] = i;
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
					assert(e !is cache.pageDescriptor.extent);

					auto ldb = binInfos[ec.sizeClass];
					auto lds = AddressRange(aptr - pd.index * PageSize,
					                        ldb.npages * PageSize);

					cache = LastDenseSlabCache(lds, pd, ldb);
					goto MarkDense;
				}

				if (ec.isLarge()) {
					if (!markLarge(pd, gcCycle)) {
						continue;
					}

					auto capacity = e.size;
					if (!pd.containsPointers || capacity < PointerSize) {
						continue;
					}

					auto range = makeRange(e.address, e.address + capacity);

					// Make sure we do not starve ourselves. If we do not have
					// work in advance, then just keep some of it for ourselves.
					if (DepthFirst && cursor == 0) {
						worklist[cursor++] = WorkItem.extractFromRange(range);
					}

					addToWorkQueue(range);
					continue;
				}

				auto se = SlabEntry(pd, ptr);
				if (!markSparse(pd, se.index, gcCycle)) {
					continue;
				}

				if (!pd.containsPointers) {
					continue;
				}

				// Make sure we do not starve ourselves. If we do not have
				// work in advance, then just keep some of it for ourselves.
				auto i = WorkItem(se.computeRange());
				if (DepthFirst && cursor == 0) {
					worklist[cursor++] = i;
				} else {
					addToWorkQueue(i);
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
	static bool markDense(PageDescriptor pd, uint index) {
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

		return e.markDenseSlot(index);
	}

	static bool markSparse(PageDescriptor pd, uint index, ubyte cycle) {
		auto e = pd.extent;
		return e.markSparseSlot(cycle, index);
	}

	static bool markLarge(PageDescriptor pd, ubyte cycle) {
		auto e = pd.extent;
		return e.markLarge(cycle);
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

	// Scan parameter.
	enum WorkUnit = 16 * PointerInPage;

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
		assert(length >= PointerSize, "WorkItem cannot be empty!");

		auto storedLength = length / PointerSize - 1;
		assert(storedLength < (1 << FreeBits), "Invalid length!");

		payload = cast(size_t) ptr;
		payload |= storedLength << LengthShift;
	}

	this(const(void*)[] range) {
		assert(range.length > 0, "WorkItem cannot be empty!");
		assert(range.length <= (1 << FreeBits), "Invalid length!");

		payload = cast(size_t) range.ptr;
		payload |= (range.length - 1) << LengthShift;
	}

	static extractFromRange(ref const(void*)[] range) {
		assert(range.length > 0, "range cannot be empty!");

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

	enum WorkUnit = WorkItem.WorkUnit;
	enum MaxUnit = 3 * WorkUnit / 2;

	foreach (size; 1 .. MaxUnit + 1) {
		auto range = (cast(const(void*)*) ptr)[0 .. size];
		auto w = WorkItem.extractFromRange(range);
		assert(w.ptr is ptr);
		assert(w.length is size * PointerSize);

		assert(range.length == 0);
	}

	foreach (size; MaxUnit + 1 .. MaxUnit + WorkUnit + 1) {
		auto range = (cast(const(void*)*) ptr)[0 .. size];
		auto w = WorkItem.extractFromRange(range);

		assert(w.ptr is ptr);
		assert(w.length is WorkUnit * PointerSize);

		assert(range.length == size - WorkUnit);

		w = WorkItem.extractFromRange(range);
		assert(w.ptr is ptr + WorkUnit * PointerSize);
		assert(w.length is (size - WorkUnit) * PointerSize);

		assert(range.length == 0);
	}
}
