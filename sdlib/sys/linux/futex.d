module sys.linux.futex;

version(linux):

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

	PrivateFlag = 128,
	ClockRealTime = 256,
	CmdMask = ~(PrivateFlag | ClockRealTime),

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

enum FutexOp {
	Set = 0,
	Add = 1,
	Or = 2,
	AndNot = 3,
	Xor = 4,
}

enum FutexOpCmp {
	EQ = 0,
	NE = 1,
	LT = 2,
	LE = 3,
	GT = 4,
	GE = 5,
}
