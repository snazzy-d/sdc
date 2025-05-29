module sys.linux.futex;

import sys.posix.types;

version(linux):
extern(C):

enum Futex {
	Wait = 0,
	Wake = 1,
	FD = 2,
	Requeue = 3,
	CmpRequeue = 4,
	WakeOp = 5,
	LockPI = 6,
	UnlockPI = 7,
	TryLockPI = 8,
	WaitBitSet = 9,
	WakeBitSet = 10,
	WaitRequeuePI = 11,
	CmpRequeuePI = 12,

	// Flags and masks.
	PrivateFlag = 128,
	ClockRealTime = 256,
	CmdMask = ~(PrivateFlag | ClockRealTime),

	// Useful combos.
	WaitPrivate = Wait | PrivateFlag,
	WakePrivate = Wake | PrivateFlag,
	RequeuePrivate = Requeue | PrivateFlag,
	CmpRequeuePrivate = CmpRequeue | PrivateFlag,
	WakeOpPrivate = WakeOp | PrivateFlag,
	LockPIPrivate = LockPI | PrivateFlag,
	UnlockPIPrivate = UnlockPI | PrivateFlag,
	TryLockPIPrivate = TryLockPI | PrivateFlag,
	WaitBitSetPrivate = WaitBitSet | PrivateFlag,
	WakeBitSetPrivate = WakeBitSet | PrivateFlag,
	WaitRequeuePIPrivate = WaitRequeuePI | PrivateFlag,
	CmpRequeuePIPrivate = CmpRequeuePI | PrivateFlag,
}

/**
 * Flags for futex2 syscalls.
 *
 * NOTE: these are not pure flags, they can also be seen as:
 *
 *   union {
 *     u32  flags;
 *     struct {
 *       u32 size    : 2,
 *           numa    : 1,
 *                   : 4,
 *           private : 1;
 *     };
 *   };
 */
enum Futex2Size {
	U8 = 0x00,
	U16 = 0x01,
	U32 = 0x02,
	U64 = 0x03,
	Numa = 0x04,
	/*	0x08 */
	/*	0x10 */
	/*	0x20 */
	/*	0x40 */

	Mask = 0x03,
}

enum FUTEX2_PRIVATE = Futex.PrivateFlag;

/**
 * Max numbers of elements in a futex_waitv array
 */
enum FUTEX_WAITV_MAX = 128;

/**
 * struct futex_waitv - A waiter for vectorized wait
 * @val:	Expected value at uaddr
 * @uaddr:	User address to wait on
 * @flags:	Flags for this waiter
 * @__reserved:	Reserved member to preserve data alignment. Should be 0.
 */
struct futex_waitv {
	ulong val;
	ulong uaddr;
	uint flags;
	uint __reserved;
}

/**
 * Support for robust futexes: the kernel cleans up held futexes at
 * thread exit time.
 */

/**
 * Per-lock list entry - embedded in user-space locks, somewhere close
 * to the futex field. (Note: user-space uses a double-linked list to
 * achieve O(1) list add and remove, but the kernel only needs to know
 * about the forward link)
 *
 * NOTE: this structure is part of the syscall ABI, and must not be
 * changed.
 */
struct robust_list {
	robust_list* next;
}

/**
 * Per-thread list head:
 *
 * NOTE: this structure is part of the syscall ABI, and must only be
 * changed if the change is first communicated with the glibc folks.
 * (When an incompatible change is done, we'll increase the structure
 *  size, which glibc will detect)
 */
struct robust_list_head {
	/**
	 * The head of the list. Points back to itself if empty:
	 */
	robust_list list;

	/**
	 * This relative offset is set by user-space, it gives the kernel
	 * the relative position of the futex field to examine. This way
	 * we keep userspace flexible, to freely shape its data-structure,
	 * without hardcoding any particular offset into the kernel:
	 */
	c_long futex_offset;

	/**
	 * The death of the thread may race with userspace setting
	 * up a lock's links. So to handle this race, userspace first
	 * sets this field to the address of the to-be-taken lock,
	 * then does the lock acquire, and then adds itself to the
	 * list, and then clears this field. Hence the kernel will
	 * always have full knowledge of all locks that the thread
	 * _might_ have taken. We check the owner TID in any case,
	 * so only truly owned locks will be handled.
	 */
	robust_list* list_op_pending;
}

/**
 * Are there any waiters for this robust futex:
 */
enum FUTEX_WAITERS = 0x80000000;

/**
 * The kernel signals via this bit that a thread holding a futex
 * has exited without unlocking the futex. The kernel also does
 * a FUTEX_WAKE on such futexes, after setting the bit, to wake
 * up any possible waiters:
 */
enum FUTEX_OWNER_DIED = 0x40000000;

/**
 * The rest of the robust-futex field is for the TID:
 */
enum FUTEX_TID_MASK = 0x3fffffff;

/**
 * This limit protects against a deliberately circular list.
 * (Not worth introducing an rlimit for it)
 */
enum ROBUST_LIST_LIMIT = 2048;

/**
 * bitset with all bits set for the FUTEX_xxx_BITSET OPs to request a
 * match of any bit.
 */
enum FUTEX_BITSET_MATCH_ANY = 0xffffffff;

enum FutexOp {
	// *(int *)UADDR2 = OPARG;
	Set = 0,
	// *(int *)UADDR2 += OPARG;
	Add = 1,
	// *(int *)UADDR2 |= OPARG;
	Or = 2,
	// *(int *)UADDR2 &= ~OPARG;
	AndNot = 3,
	// *(int *)UADDR2 ^= OPARG;
	Xor = 4,

	// Flags.
	// Use (1 << OPARG) instead of OPARG.
	OpArgShift = 8,
}

enum FutexOpCmp {
	// if (oldval == CMPARG) wake
	EQ = 0,
	// if (oldval != CMPARG) wake
	NE = 1,
	// if (oldval < CMPARG) wake
	LT = 2,
	// if (oldval <= CMPARG) wake
	LE = 3,
	// if (oldval > CMPARG) wake
	GT = 4,
	// if (oldval >= CMPARG) wake
	GE = 5,
}

/* FUTEX_WAKE_OP will perform atomically
   int oldval = *(int *)UADDR2;
   *(int *)UADDR2 = oldval OP OPARG;
   if (oldval CMP CMPARG)
     wake UADDR2;  */

extern(D) auto FUTEX_OP(FutexOp op, uint oparg, FutexOpCmp cmp, uint cmparg) {
	return (((op & 0xf) << 28) | ((cmp & 0xf) << 24) | ((oparg & 0xfff) << 12)
		| (cmparg & 0xfff));
}
