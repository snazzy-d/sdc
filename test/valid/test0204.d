//T compiles:yes
//T has-passed:yes
//T retval:0

import d.gc.signal;
import d.gc.thread;
import d.gc.tcache;
import d.gc.tstate;

import d.sync.mutex;

import core.stdc.dlfcn;
import core.stdc.errno_;
import core.stdc.pthread;

alias PthreadKillType = int function(pthread_t, int);
__gshared PthreadKillType real_pthread_kill;

shared int failSuspend = 4;
shared int failResume = 4;

extern(C) int pthread_kill(pthread_t th, int sig) {
	if (sig == SIGSUSPEND && failSuspend > 0) {
		failSuspend--;
		errno = ESRCH;
		return -1;
	}

	if (sig == SIGRESUME && failResume > 0) {
		failResume--;
		errno = ESRCH;
		return -1;
	}

	if (real_pthread_kill is null) {
		real_pthread_kill =
			cast(PthreadKillType) dlsym(RTLD_NEXT, "pthread_kill");
	}

	return real_pthread_kill(th, sig);
}

shared Mutex mutex;

void* collectorThread(void* arg) {
	auto tc = cast(ThreadCache*) arg;

	mutex.lock();
	scope(exit) mutex.unlock();

	stopTheWorld();
	assert(tc.state.suspendState == SuspendState.Suspended);
	assert(failSuspend == 0);

	restartTheWorld();
	assert(tc.state.suspendState == SuspendState.None);
	assert(failResume == 0);

	return null;
}

void main() {
	mutex.lock();

	pthread_t collector;
	auto pr = pthread_create(&collector, null, &collectorThread, &threadCache);
	assert(pr == 0, "Failed to start collector thread!");

	mutex.unlock();

	void* ret;
	pr = pthread_join(collector, &ret);
	assert(pr == 0, "Failed to join collector thread!");

	assert(threadCache.state.suspendState == SuspendState.None);
	assert(failSuspend == 0);
	assert(failResume == 0);
}
