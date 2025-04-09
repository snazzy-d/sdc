module d.gc.signal;

import d.gc.tcache;
import d.gc.tstate;

import core.stdc.signal;

enum SIGSUSPEND = SIGPWR;
enum SIGRESUME = SIGXCPU;

void setupSignals() {
	sigaction_t action;
	initSuspendSigSet(&action.sa_mask);

	action.sa_flags = SA_RESTART | SA_SIGINFO;
	action.sa_sigaction = __sd_gc_signal_suspend;

	if (sigaction(SIGSUSPEND, &action, null) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("Failed to set suspend handler!");
		exit(1);
	}

	action.sa_flags = SA_RESTART;
	action.sa_handler = __sd_gc_signal_resume;

	if (sigaction(SIGRESUME, &action, null) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("Failed to set suspend handler!");
		exit(1);
	}
}

auto signalThreadSuspend(ThreadCache* tc) {
	tc.state.sendSuspendSignal();

	// TODO: Retry on EAGAIN and handle signal loss.
	return pthread_kill(tc.self, SIGSUSPEND);
}

auto signalThreadResume(ThreadCache* tc) {
	tc.state.sendResumeSignal();

	// TODO: Retry on EAGAIN and handle signal loss.
	return pthread_kill(tc.self, SIGRESUME);
}

void suspendThreadFromSignal(ThreadState* ts) {
	/**
	 * When we suspend from the signal handler, we do not need to call
	 * __sd_gc_push_registers. The context for the signal handler has
	 * been pushed on the stack, and it contains the values for all the
	 * registers.
	 * It is capital that the signal handler uses SA_SIGINFO for this.
	 * 
	 * In addition, we do not need to mask the resume signal, because
	 * the signal handler should do that for us already.
	 */
	suspendThreadImpl(ts);
}

void suspendThreadDelayed(ThreadState* ts) {
	/**
	 * First, we make sure that a resume handler cannot be called
	 * before we suspend.
	 */
	sigset_t set, oldSet;
	initSuspendSigSet(&set);
	if (pthread_sigmask(SIG_BLOCK, &set, &oldSet) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("pthread_sigmask failed!");
		exit(1);
	}

	scope(exit) if (pthread_sigmask(SIG_SETMASK, &oldSet, null) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("pthread_sigmask failed!");
		exit(1);
	}

	/**
	 * Make sure to call __sd_gc_push_registers to make sure data
	 * in trash register will be scanned apropriately by the GC.
	 */
	import d.gc.stack;
	__sd_gc_push_registers(ts.suspendThreadImpl);
}

private:

void initSuspendSigSet(sigset_t* set) {
	if (sigfillset(set) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("sigfillset failed!");
		exit(1);
	}

	/**
	 * The signals we want to allow while in the GC's signal handler.
	 */
	if (sigdelset(set, SIGINT) != 0 || sigdelset(set, SIGQUIT) != 0
		    || sigdelset(set, SIGABRT) != 0 || sigdelset(set, SIGTERM) != 0
		    || sigdelset(set, SIGSEGV) != 0 || sigdelset(set, SIGBUS) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("sigdelset failed!");
		exit(1);
	}
}

void suspendThreadImpl(ThreadState* ts) {
	import sdc.intrinsics;
	auto stackTop = readFramePointer();

	import d.gc.hooks;
	__sd_gc_pre_suspend_hook(stackTop);
	scope(exit) __sd_gc_post_suspend_hook();

	ts.markSuspended();

	sigset_t set;
	initSuspendSigSet(&set);

	/**
	 * Suspend this thread's execution untill the resume signal is sent.
	 * 
	 * We could stop all the thread by having them wait on a mutex,
	 * but we also want to ensure that we do not run code via signals
	 * while the thread is suspended, and the mutex solution is unable
	 * to provide that guarantee, so we use sigsuspend instead.
	 */
	if (sigdelset(&set, SIGRESUME) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("sigdelset failed!");
		exit(1);
	}

	// When the resume signal is recieved, the suspend state is updated.
	while (ts.suspendState == SuspendState.Suspended) {
		sigsuspend(&set);
	}
}

extern(C) void __sd_gc_signal_suspend(int sig, siginfo_t* info, void* context) {
	// Make sure errno is preserved.
	import core.stdc.errno_;
	auto oldErrno = errno;
	scope(exit) errno = oldErrno;

	import d.gc.tcache;
	threadCache.state.onSuspendSignal();
}

extern(C) void __sd_gc_signal_resume(int sig) {
	// Make sure errno is preserved.
	import core.stdc.errno_;
	auto oldErrno = errno;
	scope(exit) errno = oldErrno;

	import d.gc.tcache;
	threadCache.state.onResumeSignal();
}
