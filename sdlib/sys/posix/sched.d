module sys.posix.sched;

version(Posix):

extern(C):
int sched_yield();
