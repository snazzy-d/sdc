module d.sync.futex.futex;

import d.sync.atomic;

import sdc.intrinsics;

import sys.linux.futex;
import core.stdc.errno_;

enum SYS_futex = 202;

int futex_wait(shared(Atomic!uint)* futex,
               uint expected, /* TODO: timeout */ ) {
	import core.stdc.unistd;
	auto err = syscall(SYS_futex, futex, Futex.WaitPrivate, expected, null);
	if (likely(err < 0)) {
		return -errno;
	}

	return 0;
}

int futex_wake(shared Atomic!uint* futex, uint count) {
	import core.stdc.unistd;
	auto err = syscall(SYS_futex, futex, Futex.WakePrivate, count);
	if (unlikely(err < 0)) {
		return -errno;
	}

	return 0;
}

int futex_wake_one(shared Atomic!uint* futex) {
	return futex_wake(futex, 1);
}

int futex_wake_all(shared Atomic!uint* futex) {
	return futex_wake(futex, uint.max);
}
