module core.stdc.signal;

import core.stdc.pthread;

import sys.posix.types;

extern(C):

/**
 * We define here all the signal names listed in POSIX (1003.1-2008);
 * as of 1003.1-2013, no additional signals have been added by POSIX.
 * We also define here signal names that historically exist in every
 * real-world POSIX variant (e.g. SIGWINCH).
 *
 * Signals in the 1-15 range are defined with their historical numbers.
 * For other signals, we use the BSD numbers.
 * There are two unallocated signal numbers in the 1-31 range: 7 and 29.
 * Signal number 0 is reserved for use as kill(pid, 0), to test whether
 * a process exists without sending it a signal.
 */
//
// ISO C99 signals.
//
// Interactive attention signal.
enum SIGINT = 2;
// Illegal instruction.
enum SIGILL = 4;
// Abnormal termination.
enum SIGABRT = 6;
// Erroneous arithmetic operation.
enum SIGFPE = 8;
// Invalid access to storage.
enum SIGSEGV = 11;
// Termination request.
enum SIGTERM = 15;

//
// Historical signals specified by POSIX.
//
// Hangup.
enum SIGHUP = 1;
// Quit.
enum SIGQUIT = 3;
// Trace/breakpoint trap.
enum SIGTRAP = 5;
// Killed.
enum SIGKILL = 9;
// Broken pipe.
enum SIGPIPE = 13;
// Alarm clock.
enum SIGALRM = 14;

//
// Archaic names for compatibility.
//
// I/O now possible (4.2 BSD).
enum SIGIO = SIGPOLL;
// IOT instruction, abort() on a PDP-11.
enum SIGIOT = SIGABRT;
// Old System V name.
enum SIGCLD = SIGCHLD;

/**
 * System specific signal numbers for Linux.
 */
//
// Adjustments and additions to the signal number constants for most Linux systems.
//
// Stack fault (obsolete).
enum SIGSTKFLT = 16;
// Power failure imminent.
enum SIGPWR = 30;

//
// Historical signals specified by POSIX.
//
// Bus error.
enum SIGBUS = 7;
// Bad system call.
enum SIGSYS = 31;

//
// New(er) POSIX signals (1003.1-2008, 1003.1-2013).
//
// Urgent data is available at a socket.
enum SIGURG = 23;
// Stop, unblockable.
enum SIGSTOP = 19;
// Keyboard stop.
enum SIGTSTP = 20;
// Continue.
enum SIGCONT = 18;
// Child terminated or stopped.
enum SIGCHLD = 17;
// Background read from control terminal.
enum SIGTTIN = 21;
// Background write to control terminal.
enum SIGTTOU = 22;
// Pollable event occurred (System V).
enum SIGPOLL = 29;
// File size limit exceeded.
enum SIGXFSZ = 25;
// CPU time limit exceeded.
enum SIGXCPU = 24;
// Virtual timer expired.
enum SIGVTALRM = 26;
// Profiling timer expired.
enum SIGPROF = 27;
// User-defined signal 1.
enum SIGUSR1 = 10;
// User-defined signal 2.
enum SIGUSR2 = 12;

//
// Nonstandard signals found in all modern POSIX systems
// (including both BSD and Linux).
//
// Window size change (4.3 BSD, Sun).
enum SIGWINCH = 28;

enum __SIGRTMIN = 32;
enum __SIGRTMAX = 64;

/**
 * Base signal features.
 */
alias sighandler_t = void function(int);
alias sigactfn_t = void function(int, siginfo_t*, void*);

// Complains about redefinition of the module name.
// sighandler_t signal(int sig, sighandler_t handler)

int kill(pid_t pid, int sig);
int killpg(pid_t pgrp, int signal);
int raise(int sig);

void psignal(int sig, const char* s);
void psiginfo(const siginfo_t* pinfo, const char* s);

/**
 * Sigset manipulations.
 */
enum SIGSET_NWORDS = 1024 / (8 * c_ulong.sizeof);

struct sigset_t {
	c_ulong[SIGSET_NWORDS] __val;
}

int sigemptyset(sigset_t* set);
int sigfillset(sigset_t* set);
int sigaddset(sigset_t* set, int signum);
int sigdelset(sigset_t* set, int signum);
int sigismember(const sigset_t* set, int signum);

/**
 * Functionalities relying on sigset.
 */
//
// Values for the HOW argument to `sigprocmask'.
//
// Block signals.
enum SIG_BLOCK = 0;
// Unblock signals.
enum SIG_UNBLOCK = 1;
// Set the set of blocked signals.
enum SIG_SETMASK = 2;

int sigprocmask(int how, const sigset_t* set, sigset_t* oldset);
int sigsuspend(const sigset_t* sigmask);
int sigpending(sigset_t* set);

/**
 * sigaction.
 */
struct sigaction_t {
	// Signal handler.
	union __sigaction_handler_t {
		// Used if SA_SIGINFO is not set.
		sighandler_t sa_handler;
		// Used if SA_SIGINFO is set.
		sigactfn_t sa_sigaction;
	}

	__sigaction_handler_t __sigaction_handler;
	alias __sigaction_handler this;

	// Additional set of signals to be blocked.
	sigset_t sa_mask;

	// Special flags.
	int sa_flags;

	// Restore handler.
	void function() sa_restorer;
}

//
// Bits in `sa_flags'.
//
// Don't send SIGCHLD when children stop.
enum SA_NOCLDSTOP = 1;
// Don't create zombie on child death.
enum SA_NOCLDWAIT = 2;
// Invoke signal-catching function with three arguments instead of one.
enum SA_SIGINFO = 4;

// Use signal stack by using `sa_restorer'.
enum SA_ONSTACK = 0x08000000;
// Restart syscall on signal return.
enum SA_RESTART = 0x10000000;
// Don't automatically block the signal when its handler is being executed.
enum SA_NODEFER = 0x40000000;
// Reset to SIG_DFL on entry to handler.
enum SA_RESETHAND = 0x80000000;
// Historical no-op.
enum SA_INTERRUPT = 0x20000000;

// Some aliases for the SA_ constants.
enum SA_NOMASK = SA_NODEFER;
enum SA_ONESHOT = SA_RESETHAND;
enum SA_STACK = SA_ONSTACK;

int sigaction(int sig, const sigaction_t* act, sigaction_t* oldact);

/**
 * Time based functionalities.
 * Rely on timespec_t which is not portad at this time.
 */
int sigwait(const sigset_t* set, int* sig);
int sigwaitinfo(const sigset_t* set, siginfo_t* info);
// int sigtimedwait(const sigset_t* set, siginfo_t* info,
//                  const timespec_t* timeout);

/**
 * sigval functionalities.
 */
union sigval_t {
	void* sival_ptr;
	int sival_int;
}

int sigqueue(pid_t pid, int sig, const sigval_t value);

/**
 * Signal stack.
 */
// Linux specific, non portable. Prefer sigaltstack.
// int sigreturn(sigcontext_t* scp)

struct stack_t {
	void* ss_sp;
	int ss_flags;
	size_t ss_size;
}

int sigaltstack(const stack_t* ss, stack_t* olsss);

/**
 * pthread functionalities.
 */
int pthread_kill(pthread_t thread, int sig);
int pthread_sigmask(int how, const sigset_t* set, sigset_t* oldset);
int pthread_sigqueue(pthread_t* thread, int sig, const sigval_t value);

/**
 * Siginfo defintiion.
 */
enum __SI_MAX_SIZE = 128;
enum __SI_PAD_SIZE = ((__SI_MAX_SIZE / int.sizeof) - 4);
static assert(__SI_PAD_SIZE % 2 == 0,
              "__SI_PAD_SIZE must be even to pad with ulong for alignment.");

struct siginfo_t {
	int si_signo;
	int si_errno;
	int si_code;
	int __pad0;

	union _sifields_t {
		// This differs from the C declaration,
		// but is required for alignement purposes.
		ulong[__SI_PAD_SIZE / 2] _ulong_pad;

		int[__SI_PAD_SIZE] _pad;

		// kill().
		struct _kill_t {
			// Sending process ID.
			pid_t si_pid;
			// Real user ID of sending process.
			uid_t si_uid;
		}

		_kill_t _kill;

		// POSIX.1b timers.
		struct _timer_t {
			// Timer ID.
			int si_tid;
			// Overrun count.
			int si_overrun;
			// Signal value.
			sigval_t si_sigval;
		}

		_timer_t _timer;

		// POSIX.1b signals.
		struct _rt_t {
			// Sending process ID.
			pid_t si_pid;
			// Real user ID of sending process.
			uid_t si_uid;
			// Signal value.
			sigval_t si_sigval;
		}

		_rt_t _rt;

		// SIGCHLD.
		struct _sigchld_t {
			// Which child.
			pid_t si_pid;
			// Real user ID of sending process.
			uid_t si_uid;
			// Exit value or signal.
			int si_status;
			clock_t si_utime;
			clock_t si_stime;
		}

		_sigchld_t _sigchld;

		// SIGILL, SIGFPE, SIGSEGV, SIGBUS.
		struct _sigfault_t {
			// Faulting insn/memory ref.
			void* si_addr;
			// Valid LSB of the reported address.
			short si_addr_lsb;
			union _bounds_t {
				// used when si_code=SEGV_BNDERR
				struct _addr_bnd_t {
					void* _lower;
					void* _upper;
				}

				_addr_bnd_t _addr_bnd;
				// used when si_code=SEGV_PKUERR
				uint _pkey;
			}

			_bounds_t _bounds;
		}

		_sigfault_t _sigfault;

		// SIGPOLL.
		struct _sigpoll_t {
			// Band event for SIGPOLL.
			c_long si_band;
			int si_fd;
		}

		_sigpoll_t _sigpoll;

		// SIGSYS.
		struct _sigsys_t {
			// Calling user insn.
			void* _call_addr;
			// Triggering system call number.
			int _syscall;
			// AUDIT_ARCH_* of syscall.
			uint _arch;
		}

		_sigsys_t _sigsys;
	}

	_sifields_t _sifields;
}
