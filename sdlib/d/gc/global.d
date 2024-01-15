import d.gc.global;

struct GCState {
private:
	import d.sync.mutex;
	Mutex mutex;

	const(void*)[][] roots;

public:
	void addRoots(const void[] range) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(GCState*) &this).addRootsImpl(range);
	}

private:
	void addRootsImpl(const void[] range) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto ptr = cast(void*) roots.ptr;

		// We realloc everytime. It doesn't really matter at this point.
		import d.gc.tcache;
		roots.ptr = cast(const(void*)[]*)
			threadCache.realloc(ptr, (roots.length + 1) * void*[].sizeof, true);

		// Using .ptr to bypass bound checking.
		import d.gc.range;
		roots.ptr[roots.length] = makeRange(range);

		// Update the range.
		roots = roots.ptr[0 .. roots.length + 1];
	}
}

shared GCState gState;
