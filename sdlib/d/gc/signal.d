module d.gc.signal;

import d.gc.tcache;

import core.stdc.signal;

enum SIGSUSPEND = SIGPWR;

// Not used at the moment.
enum SIGRESUME = SIGXCPU;

void setupSignals() {
	sigaction_t action;
	initSigSet(&action.sa_mask);
	action.sa_flags = SA_RESTART | SA_SIGINFO;
	action.sa_sigaction = __sd_gc_signal_suspend;

	if (sigaction(SIGSUSPEND, &action, null) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("Failed to set suspend handler!");
		exit(1);
	}
}

auto signalThread(ThreadCache* tc) {
	tc.state.sendSignal();

	// TODO: Retry on EAGAIN and handle signal loss.
	return pthread_kill(tc.self, SIGSUSPEND);
}

private:

void initSigSet(sigset_t* set) {
	if (sigfillset(set) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("sigfillset failed!");
		exit(1);
	}

	if (sigdelset(set, SIGINT) != 0 || sigdelset(set, SIGQUIT) != 0
		    || sigdelset(set, SIGABRT) != 0 || sigdelset(set, SIGTERM) != 0
		    || sigdelset(set, SIGSEGV) != 0 || sigdelset(set, SIGBUS) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("sigdelset failed!");
		exit(1);
	}
}

extern(C) void __sd_gc_signal_suspend(int sig, siginfo_t* info, void* context) {
	// Make sure errno is preserved.
	import core.stdc.errno_;
	auto olderrno = errno;
	scope(exit) errno = olderrno;

	import d.gc.tcache;
	threadCache.state.recieveSignal();
}
