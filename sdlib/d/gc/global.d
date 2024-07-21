import d.gc.global;

alias ScanDg = void delegate(const(void*)[] range);

struct GCState {
private:
	import d.sync.atomic;
	Atomic!ubyte cycle;

	import d.sync.mutex;
	Mutex mutex;

	const(void*)[][] roots;

public:
	ubyte nextGCCycle() shared {
		auto c = cycle.fetchAdd(1);
		return (c + 1) & ubyte.max;
	}

    /**
     * Add a block of scannable data as a root to possible GC memory. This
     * range will be scanned on proper alignment boundaries if it potentially
     * could contain pointers.
     *
     * If it has a length of 0, then the range is added as-is, to allow pinning
     * of GC blocks. These blocks will be scanned as part of the normal
     * process, by virtue of the pointer being stored as a range of 0 bytes in
     * the global array of roots.
     */
	void addRoots(const void[] range) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(GCState*) &this).addRootsImpl(range);
	}

    /**
     * Remove the root (if present) that begins with the given pointer.
     */
	void removeRoots(const void* ptr) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(GCState*) &this).removeRootsImpl(ptr);
	}

	void scanRoots(ScanDg scan) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(GCState*) &this).scanRootsImpl(scan);
	}

private:
	void addRootsImpl(const void[] range) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto ptr = cast(void*) roots.ptr;
		auto index = roots.length;
		auto length = index + 1;

		// We realloc everytime. It doesn't really matter at this point.
		import d.gc.tcache;
		ptr = threadCache.realloc(ptr, length * void*[].sizeof, true);
		roots = (cast(const(void*)[]*) ptr)[0 .. length];

		import d.gc.range;
		if (range.length == 0) {
			roots[index] = cast(void*[]) range;
		} else {
			roots[index] = makeRange(range);
		}
	}

	void removeRootsImpl(const void* ptr) {
		assert(mutex.isHeld(), "Mutex not held!");

		/*
         * Search in reverse, since it's most likely for things to be removed
         * in the reverse order they were added.
         */
		foreach_reverse (i; 0 .. roots.length) {
			if (cast(void*) roots[i].ptr == ptr) {
				auto length = roots.length - 1;
				roots[i] = roots[length];
				import d.gc.tcache;
				auto newRoots = threadCache
					.realloc(roots.ptr, length * void*[].sizeof, true);
				roots = (cast(const(void*)[]*) newRoots)[0 .. length];
				return;
			}
		}
	}

	void scanRootsImpl(ScanDg scan) {
		assert(mutex.isHeld(), "Mutex not held!");

		foreach (range; roots) {
			/*
             * Adding a range of length 0 is like pinning the given range
             * address. This is scanned when the roots array itself is scanned
             * (because it's referred to from the global segment). Therefore,
             * we can skip the marking of that pointer.
             */
			if (range.length > 0) {
				scan(range);
			}
		}
	}
}

shared GCState gState;
