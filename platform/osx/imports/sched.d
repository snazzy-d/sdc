// FIXME: On OSX, this is a symlink to pthread/sched.h
module sched;

extern(C):

// FIXME: defined in pthread/pthread_impl.h
enum __SCHED_PARAM_SIZE__ = 4;

struct sched_param {
	int sched_priority;
	byte[__SCHED_PARAM_SIZE__] __opaque;
}

int sched_yield();
int sched_get_priority_min(int);
int sched_get_priority_max(int);
