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

	void addRoots(const void[] range) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(GCState*) &this).addRootsImpl(range);
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

		// We realloc everytime. It doesn't really matter at this point.
		import d.gc.tcache;
		roots.ptr = cast(const(void*)[]*)
			threadCache.realloc(ptr, (roots.length + 1) * void*[].sizeof, true);
		roots = roots.ptr[0 .. index + 1];

		import d.gc.range;
		roots[index] = makeRange(range);
	}

	void scanRootsImpl(ScanDg scan) {
		assert(mutex.isHeld(), "Mutex not held!");

		foreach (range; roots) {
			scan(range);
		}
	}
}

shared GCState gState;
