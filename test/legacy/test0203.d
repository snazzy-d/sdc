//T compiles:yes
//T has-passed:yes
//T retval:0
// Check sending spurious signals to the GC do not mess it up.

import d.gc.signal;
import d.gc.tcache;
import d.gc.tstate;

import core.stdc.pthread;
import core.stdc.sched;
import core.stdc.signal;
import core.stdc.stdlib;
import core.stdc.sys.wait;
import core.stdc.unistd;

void checkUnchanged(ThreadState* s, string loc) {
	assert(s.suspendState == SuspendState.None, loc);
	assert(!s.busy, loc);
}

void sendBoth(string loc, int delegate(int sig) send) {
	auto s = &threadCache.state;

	// printf("SIGSUSPEND via %s\n", loc.ptr);
	auto r = send(SIGSUSPEND);
	assert(r == 0, loc);
	checkUnchanged(s, loc);

	// printf("SIGRESUME via %s\n", loc.ptr);
	r = send(SIGRESUME);
	assert(r == 0, loc);
	checkUnchanged(s, loc);
}

void* workerLoop(void* arg) {
	auto stop = cast(shared uint*) arg;

	// Publish this thread's state so the main thread can check it.
	auto s = &threadCache.state;

	import d.sync.atomic;
	// *stop == 0: running, 1: main has inspected, 2: exit
	while (*stop == 0) {
		sched_yield();
	}

	checkUnchanged(s, "worker after foreign signals");

	while (*stop == 1) {
		sched_yield();
	}

	return null;
}

void main() {
	auto s = &threadCache.state;
	checkUnchanged(s, "init");

	// kill(getpid()) — process-directed, SI_USER
	sendBoth("kill(getpid())", (int sig) => kill(getpid(), sig));

	// raise() — self, SI_TKILL on Linux (tgkill)
	sendBoth("raise()", (int sig) => raise(sig));

	// pthread_kill(self) — thread-directed, SI_TKILL
	auto self = pthread_self();
	sendBoth("pthread_kill(self)", (int sig) => pthread_kill(self, sig));

	// sigqueue(getpid()) — process-directed, SI_QUEUE
	sendBoth("sigqueue(getpid())", (int sig) {
		sigval_t value;
		value.sival_int = 0;
		return sigqueue(getpid(), sig, value);
	});

	// killpg(getpgrp()) — process-group, SI_USER
	// Own process group: killpg must not signal the test runner.
	auto pg = setpgid(0, 0);
	assert(pg == 0, "setpgid failed!");
	sendBoth("killpg(getpgrp())", (int sig) => killpg(getpgrp(), sig));

	// child kill(parent) — other process, SI_USER
	auto parent = getpid();
	auto child = fork();
	assert(child >= 0, "fork failed!");
	if (child == 0) {
		auto kr = kill(parent, SIGSUSPEND);
		if (kr == 0) {
			kr = kill(parent, SIGRESUME);
		}

		exit(kr == 0 ? 0 : 1);
	}

	int status = 0;
	auto w = waitpid(child, &status, 0);
	assert(w == child, "waitpid failed!");
	assert(status == 0, "child kill failed!");
	checkUnchanged(s, "child kill(parent)");

	// pthread_kill(worker) — other thread, SI_TKILL
	shared uint stop = 0;
	pthread_t worker;
	auto pr = pthread_create(&worker, null, workerLoop, cast(void*) &stop);
	assert(pr == 0, "pthread_create failed!");

	// Process-directed hits an arbitrary unblocked thread.
	auto r = kill(getpid(), SIGSUSPEND);
	assert(r == 0);
	r = kill(getpid(), SIGRESUME);
	assert(r == 0);

	r = pthread_kill(worker, SIGSUSPEND);
	assert(r == 0);
	r = pthread_kill(worker, SIGRESUME);
	assert(r == 0);

	checkUnchanged(s, "main after worker-targeted signals");

	stop = 1;
	sched_yield();
	stop = 2;

	void* ret;
	pr = pthread_join(worker, &ret);
	assert(pr == 0, "pthread_join failed!");

	checkUnchanged(s, "final");
}
