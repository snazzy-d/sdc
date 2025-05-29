module d.gc.cpu;

auto getCoreCount() {
	auto coreCountPtr = cast(uint*) &gCoreCount;
	if (*coreCountPtr == 0) {
		*coreCountPtr = computeCoreCount();
	}

	return *coreCountPtr;
}

private:
shared uint gCoreCount;

auto computeCoreCount() {
	import sched;
	cpu_set_t set;
	sched_getaffinity(0, cpu_set_t.sizeof, &set);
	return CPU_COUNT(&set);
}

unittest getCoreCount {
	import sys.linux.sysinfo;
	assert(getCoreCount() == get_nprocs());
}
