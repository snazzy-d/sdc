//T compiles:yes
//T has-passed:yes
//T retval:0
// GC unsuspendable thread test.

import d.sync.mutex;
shared Mutex m1, m2;

extern(C) void __sd_gc_collect();

void* runThread(void*) {
	m2.lock();

	import core.stdc.signal;
	sigset_t set;
	sigfillset(&set);

	// Block all signals!
	import core.stdc.pthread;
	pthread_sigmask(SIG_BLOCK, &set, null);

	// Hand over to the main thread.
	m1.unlock();

	// Wait for the main thread to collect.
	m2.lock();
	m2.unlock();

	return null;
}

void main() {
	m1.lock();

	import core.stdc.pthread;
	pthread_t tid;
	pthread_create(&tid, null, runThread, null);

	// Wait for the thread ot start.
	m1.lock();
	m1.unlock();

	__sd_gc_collect();

	m2.unlock();

	void* ret;
	pthread_join(tid, &ret);
}
