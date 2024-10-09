module sys.posix.sched;

import sys.posix.types;

version(Posix):
extern(C):

int sched_yield();
int sched_getcpu();

alias __cpu_mask = c_ulong;

enum __CPU_SETSIZE = 1024;
enum __NCPUBITS = 8 * __cpu_mask.sizeof;

struct cpu_set_t {
	__cpu_mask[__CPU_SETSIZE / __NCPUBITS] __bits;
}

int sched_setaffinity(pid_t pid, size_t cpusetsize, const cpu_set_t* mask);
int sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t* mask);

/**
 * sched.h contains various macros. D does not have macros,
 * so we use several parameterless templates instead.
 */
extern(D):

int CPU_COUNT()(const cpu_set_t* setp) {
	int result = 0;

	foreach (n; setp.__bits) {
		import sdc.intrinsics;
		result += popCount(n);
	}

	return result;
}
