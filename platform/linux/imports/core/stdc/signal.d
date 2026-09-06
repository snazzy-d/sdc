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

/*
 * How these fields are to be accessed.
 */
/+
#define si_pid          _sifields._kill._pid
#define si_uid          _sifields._kill._uid
#define si_tid          _sifields._timer._tid
#define si_overrun      _sifields._timer._overrun
#define si_sys_private  _sifields._timer._sys_private
#define si_status       _sifields._sigchld._status
#define si_utime        _sifields._sigchld._utime
#define si_stime        _sifields._sigchld._stime
#define si_value        _sifields._rt._sigval
#define si_int          _sifields._rt._sigval.sival_int
#define si_ptr          _sifields._rt._sigval.sival_ptr
#define si_addr         _sifields._sigfault._addr
#define si_trapno       _sifields._sigfault._trapno
#define si_addr_lsb     _sifields._sigfault._addr_lsb
#define si_lower        _sifields._sigfault._addr_bnd._lower
#define si_upper        _sifields._sigfault._addr_bnd._upper
#define si_pkey         _sifields._sigfault._addr_pkey._pkey
#define si_perf_data    _sifields._sigfault._perf._data
#define si_perf_type    _sifields._sigfault._perf._type
#define si_perf_flags   _sifields._sigfault._perf._flags
#define si_band         _sifields._sigpoll._band
#define si_fd           _sifields._sigpoll._fd
#define si_call_addr    _sifields._sigsys._call_addr
#define si_syscall      _sifields._sigsys._syscall
#define si_arch         _sifields._sigsys._arch
// +/

/*
 * si_code values
 * Digital reserves positive values for kernel-generated signals.
 */
enum SI_USER = 0; /* sent by kill, sigsend, raise */
enum SI_KERNEL = 0x80; /* sent by the kernel from somewhere */
enum SI_QUEUE = -1; /* sent by sigqueue */
enum SI_TIMER = -2; /* sent by timer expiration */
enum SI_MESGQ = -3; /* sent by real time mesq state change */
enum SI_ASYNCIO = -4; /* sent by AIO completion */
enum SI_SIGIO = -5; /* sent by queued SIGIO */
enum SI_TKILL = -6; /* sent by tkill system call */
enum SI_DETHREAD = -7; /* sent by execve() killing subsidiary threads */
enum SI_ASYNCNL = -60; /* sent by glibc async name lookup completion */

bool SI_FROMUSER()(siginfo_t* siptr) {
	return siptr.si_code <= 0;
}

bool SI_FROMKERNEL()(siginfo_t* siptr) {
	return siptr.si_code > 0;
}

/*
 * SIGILL si_codes
 */
enum ILL_ILLOPC = 1; /* illegal opcode */
enum ILL_ILLOPN = 2; /* illegal operand */
enum ILL_ILLADR = 3; /* illegal addressing mode */
enum ILL_ILLTRP = 4; /* illegal trap */
enum ILL_PRVOPC = 5; /* privileged opcode */
enum ILL_PRVREG = 6; /* privileged register */
enum ILL_COPROC = 7; /* coprocessor error */
enum ILL_BADSTK = 8;/* internal stack error */
enum ILL_BADIADDR = 9; /* unimplemented instruction address */
enum __ILL_BREAK = 10; /* illegal break */
enum __ILL_BNDMOD = 11; /* bundle-update (modification) in progress */
enum NSIGILL = 11;

/*
 * SIGFPE si_codes
 */
enum FPE_INTDIV = 1; /* integer divide by zero */
enum FPE_INTOVF = 2; /* integer overflow */
enum FPE_FLTDIV = 3; /* floating point divide by zero */
enum FPE_FLTOVF = 4; /* floating point overflow */
enum FPE_FLTUND = 5; /* floating point underflow */
enum FPE_FLTRES = 6; /* floating point inexact result */
enum FPE_FLTINV = 7; /* floating point invalid operation */
enum FPE_FLTSUB = 8;/* subscript out of range */
enum __FPE_DECOVF = 9; /* decimal overflow */
enum __FPE_DECDIV = 10; /* decimal division by zero */
enum __FPE_DECERR = 11; /* packed decimal error */
enum __FPE_INVASC = 12; /* invalid ASCII digit */
enum __FPE_INVDEC = 13; /* invalid decimal digit */
enum FPE_FLTUNK = 14; /* undiagnosed floating-point exception */
enum FPE_CONDTRAP = 15; /* trap on condition */
enum NSIGFPE = 15;

/*
 * SIGSEGV si_codes
 */
enum SEGV_MAPERR = 1; /* address not mapped to object */
enum SEGV_ACCERR = 2; /* invalid permissions for mapped object */
enum SEGV_BNDERR = 3; /* failed address bound checks */
/+
#ifdef __ia64__
enum __SEGV_PSTKOVF = 4; /* paragraph stack overflow */
#else
enum SEGV_PKUERR = 4; /* failed protection key checks */
#endif
// +/
enum SEGV_ACCADI = 5; /* ADI not enabled for mapped object */
enum SEGV_ADIDERR = 6; /* Disrupting MCD error */
enum SEGV_ADIPERR = 7; /* Precise MCD exception */
enum SEGV_MTEAERR = 8;/* Asynchronous ARM MTE error */
enum SEGV_MTESERR = 9; /* Synchronous ARM MTE exception */
enum SEGV_CPERR = 10;/* Control protection fault */
enum NSIGSEGV = 10;

/*
 * SIGBUS si_codes
 */
enum BUS_ADRALN = 1; /* invalid address alignment */
enum BUS_ADRERR = 2; /* non-existent physical address */
enum BUS_OBJERR = 3; /* object specific hardware error */
/* hardware memory error consumed on a machine check: action required */
enum BUS_MCEERR_AR = 4;
/* hardware memory error detected in process but not consumed: action optional*/
enum BUS_MCEERR_AO = 5;
enum NSIGBUS = 5;

/*
 * SIGTRAP si_codes
 */
enum TRAP_BRKPT = 1; /* process breakpoint */
enum TRAP_TRACE = 2; /* process trace trap */
enum TRAP_BRANCH = 3; /* process taken branch trap */
enum TRAP_HWBKPT = 4; /* hardware breakpoint/watchpoint */
enum TRAP_UNK = 5; /* undiagnosed trap */
enum TRAP_PERF = 6; /* perf event with sigtrap=1 */
enum NSIGTRAP = 6;

/*
 * There is an additional set of SIGTRAP si_codes used by ptrace
 * that are of the form: ((PTRACE_EVENT_XXX << 8) | SIGTRAP)
 */

/*
 * Flags for si_perf_flags if SIGTRAP si_code is TRAP_PERF.
 */
enum TRAP_PERF_FLAG_ASYNC = 1u << 0;

/*
 * SIGCHLD si_codes
 */
enum CLD_EXITED = 1; /* child has exited */
enum CLD_KILLED = 2; /* child was killed */
enum CLD_DUMPED = 3; /* child terminated abnormally */
enum CLD_TRAPPED = 4; /* traced child has trapped */
enum CLD_STOPPED = 5; /* child has stopped */
enum CLD_CONTINUED = 6; /* stopped child has continued */
enum NSIGCHLD = 6;

/*
 * SIGPOLL (or any other signal without signal specific si_codes) si_codes
 */
enum POLL_IN = 1; /* data input available */
enum POLL_OUT = 2; /* output buffers available */
enum POLL_MSG = 3; /* input message available */
enum POLL_ERR = 4; /* i/o error */
enum POLL_PRI = 5; /* high priority input available */
enum POLL_HUP = 6; /* device disconnected */
enum NSIGPOLL = 6;

/*
 * SIGSYS si_codes
 */
enum SYS_SECCOMP = 1; /* seccomp triggered */
enum SYS_USER_DISPATCH = 2; /* syscall user dispatch triggered */
enum NSIGSYS = 2;

/*
 * SIGEMT si_codes
 */
enum EMT_TAGOVF = 1; /* tag overflow */
enum NSIGEMT = 1;

/*
 * sigevent definitions
 *
 * It seems likely that SIGEV_THREAD will have to be handled from
 * userspace, libpthread transmuting it to SIGEV_SIGNAL, which the
 * thread manager then catches and does the appropriate nonsense.
 * However, everything is written out here so as to not get lost.
 */
enum SIGEV_SIGNAL = 0; /* notify via signal */
enum SIGEV_NONE = 1; /* other notification: meaningless */
enum SIGEV_THREAD = 2; /* deliver via thread creation */
enum SIGEV_THREAD_ID = 4; /* deliver to thread */

/*
 * This works because the alignment is ok on all current architectures
 * but we leave open this being overridden in the future
 */
enum __ARCH_SIGEV_PREAMBLE_SIZE = 2 * int.sizeof + sigval_t.sizeof;

enum SIGEV_MAX_SIZE = 64;
enum SIGEV_PAD_SIZE =
	(SIGEV_MAX_SIZE - __ARCH_SIGEV_PREAMBLE_SIZE) / int.sizeof;

struct sigevent_t {
	sigval_t sigev_value;
	int sigev_signo;
	int sigev_notify;

	union _sigev_un_t {
		// This differs from the C declaration,
		// but is required for alignement purposes.
		ulong[SIGEV_PAD_SIZE / 2] _ulong_pad;

		int[SIGEV_PAD_SIZE] _pad;
		int _tid;

		struct _sigev_thread_t {
			void function(sigval_t) _function;
			void* _attribute; /* really pthread_attr_t */
		}

		_sigev_thread_t _sigev_thread;
	}

	_sigev_un_t _sigev_un;
}

/+
#define sigev_notify_function   _sigev_un._sigev_thread._function
#define sigev_notify_attributes _sigev_un._sigev_thread._attribute
#define sigev_notify_thread_id   _sigev_un._tid
// +/
