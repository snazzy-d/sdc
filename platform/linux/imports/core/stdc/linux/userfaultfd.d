module core.stdc.linux.userfaultfd;

import sys.posix.types;
import core.stdc.linux.ioctl;

extern(C):

/* ioctls for /dev/userfaultfd */
enum USERFAULTFD_IOC = 0xAA;
enum USERFAULTFD_IOC_NEW = _IO!(USERFAULTFD_IOC, 0x00);

/*
 * If the UFFDIO_API is upgraded someday, the UFFDIO_UNREGISTER and
 * UFFDIO_WAKE ioctls should be defined as _IOW and not as _IOR.  In
 * userfaultfd.h we assumed the kernel was reading (instead _IOC_READ
 * means the userland is reading).
 */
enum ulong UFFD_API = 0xAA;
enum UFFD_API_REGISTER_MODES = UFFDIO_REGISTER_MODE_MISSING
	| UFFDIO_REGISTER_MODE_WP | UFFDIO_REGISTER_MODE_MINOR;
enum UFFD_API_FEATURES = UFFD_FEATURE_PAGEFAULT_FLAG_WP
	| UFFD_FEATURE_EVENT_FORK | UFFD_FEATURE_EVENT_REMAP
	| UFFD_FEATURE_EVENT_REMOVE | UFFD_FEATURE_EVENT_UNMAP
	| UFFD_FEATURE_MISSING_HUGETLBFS | UFFD_FEATURE_MISSING_SHMEM
	| UFFD_FEATURE_SIGBUS | UFFD_FEATURE_THREAD_ID
	| UFFD_FEATURE_MINOR_HUGETLBFS | UFFD_FEATURE_MINOR_SHMEM
	| UFFD_FEATURE_EXACT_ADDRESS | UFFD_FEATURE_WP_HUGETLBFS_SHMEM
	| UFFD_FEATURE_WP_UNPOPULATED | UFFD_FEATURE_POISON | UFFD_FEATURE_WP_ASYNC
	| UFFD_FEATURE_MOVE;
enum UFFD_API_IOCTLS = ulong(1) << _UFFDIO_REGISTER
	| ulong(1) << _UFFDIO_UNREGISTER | ulong(1) << _UFFDIO_API;
enum UFFD_API_RANGE_IOCTLS = ulong(1) << _UFFDIO_WAKE | ulong(1) << _UFFDIO_COPY
	| ulong(1) << _UFFDIO_ZEROPAGE | ulong(1) << _UFFDIO_MOVE
	| ulong(1) << _UFFDIO_WRITEPROTECT | ulong(1) << _UFFDIO_CONTINUE
	| ulong(1) << _UFFDIO_POISON;
enum UFFD_API_RANGE_IOCTLS_BASIC = ulong(1) << _UFFDIO_WAKE
	| ulong(1) << _UFFDIO_COPY | ulong(1) << _UFFDIO_WRITEPROTECT
	| ulong(1) << _UFFDIO_CONTINUE | ulong(1) << _UFFDIO_POISON;

/*
 * Valid ioctl command number range with this API is from 0x00 to
 * 0x3F.  UFFDIO_API is the fixed number, everything else can be
 * changed by implementing a different UFFD_API. If sticking to the
 * same UFFD_API more ioctl can be added and userland will be aware of
 * which ioctl the running kernel implements through the ioctl command
 * bitmask written by the UFFDIO_API.
 */
enum _UFFDIO_REGISTER = 0x00;
enum _UFFDIO_UNREGISTER = 0x01;
enum _UFFDIO_WAKE = 0x02;
enum _UFFDIO_COPY = 0x03;
enum _UFFDIO_ZEROPAGE = 0x04;
enum _UFFDIO_MOVE = 0x05;
enum _UFFDIO_WRITEPROTECT = 0x06;
enum _UFFDIO_CONTINUE = 0x07;
enum _UFFDIO_POISON = 0x08;
enum _UFFDIO_API = 0x3F;

/* userfaultfd ioctl ids */
enum UFFDIO = 0xAA;
enum UFFDIO_API = _IOWR!(UFFDIO, _UFFDIO_API, uffdio_api);
enum UFFDIO_REGISTER = _IOWR!(UFFDIO, _UFFDIO_REGISTER, uffdio_register);
enum UFFDIO_UNREGISTER = _IOR!(UFFDIO, _UFFDIO_UNREGISTER, uffdio_range);
enum UFFDIO_WAKE = _IOR!(UFFDIO, _UFFDIO_WAKE, uffdio_range);
enum UFFDIO_COPY = _IOWR!(UFFDIO, _UFFDIO_COPY, uffdio_copy);
enum UFFDIO_ZEROPAGE = _IOWR!(UFFDIO, _UFFDIO_ZEROPAGE, uffdio_zeropage);
enum UFFDIO_MOVE = _IOWR!(UFFDIO, _UFFDIO_MOVE, uffdio_move);
enum UFFDIO_WRITEPROTECT =
	_IOWR!(UFFDIO, _UFFDIO_WRITEPROTECT, uffdio_writeprotect);
enum UFFDIO_CONTINUE = _IOWR!(UFFDIO, _UFFDIO_CONTINUE, uffdio_continue);
enum UFFDIO_POISON = _IOWR!(UFFDIO, _UFFDIO_POISON, uffdio_poison);

/* read() structure */
struct uffd_msg {
	__u8 event;

	__u8 reserved1;
	__u16 reserved2;
	__u32 reserved3;

	union arg_t {
		struct pagefault_t {
			__u64 flags;
			__u64 address;
			union feat_t {
				__u32 ptid;
			}

			feat_t feat;
		}

		pagefault_t pagefault;

		struct fork_t {
			__u32 ufd;
		}

		fork_t fork;

		struct remap_t {
			__u64 from;
			__u64 to;
			__u64 len;
		}

		remap_t remap;

		struct remove_t {
			__u64 start;
			__u64 end;
		}

		remove_t remove;

		struct reserved_t {
			/* unused reserved fields */
			__u64 reserved1;
			__u64 reserved2;
			__u64 reserved3;
		}

		reserved_t reserved;
	}

	arg_t arg;
} // __attribute__((packed));

/*
 * Start at 0x12 and not at 0 to be more strict against bugs.
 */
enum UFFD_EVENT_PAGEFAULT = 0x12;
enum UFFD_EVENT_FORK = 0x13;
enum UFFD_EVENT_REMAP = 0x14;
enum UFFD_EVENT_REMOVE = 0x15;
enum UFFD_EVENT_UNMAP = 0x16;

/* flags for UFFD_EVENT_PAGEFAULT */
enum UFFD_PAGEFAULT_FLAG_WRITE = 1 << 0; /* If this was a write fault */
enum UFFD_PAGEFAULT_FLAG_WP = 1 << 1; /* If reason is VM_UFFD_WP */
enum UFFD_PAGEFAULT_FLAG_MINOR = 1 << 2; /* If reason is VM_UFFD_MINOR */

struct uffdio_api {
	/* userland asks for an API number and the features to enable */
	__u64 api;
	/*
	 * Kernel answers below with the all available features for
	 * the API, this notifies userland of which events and/or
	 * which flags for each event are enabled in the current
	 * kernel.
	 *
	 * Note: UFFD_EVENT_PAGEFAULT and UFFD_PAGEFAULT_FLAG_WRITE
	 * are to be considered implicitly always enabled in all kernels as
	 * long as the uffdio_api.api requested matches UFFD_API.
	 *
	 * UFFD_FEATURE_MISSING_HUGETLBFS means an UFFDIO_REGISTER
	 * with UFFDIO_REGISTER_MODE_MISSING mode will succeed on
	 * hugetlbfs virtual memory ranges. Adding or not adding
	 * UFFD_FEATURE_MISSING_HUGETLBFS to uffdio_api.features has
	 * no real functional effect after UFFDIO_API returns, but
	 * it's only useful for an initial feature set probe at
	 * UFFDIO_API time. There are two ways to use it:
	 *
	 * 1) by adding UFFD_FEATURE_MISSING_HUGETLBFS to the
	 *    uffdio_api.features before calling UFFDIO_API, an error
	 *    will be returned by UFFDIO_API on a kernel without
	 *    hugetlbfs missing support
	 *
	 * 2) the UFFD_FEATURE_MISSING_HUGETLBFS can not be added in
	 *    uffdio_api.features and instead it will be set by the
	 *    kernel in the uffdio_api.features if the kernel supports
	 *    it, so userland can later check if the feature flag is
	 *    present in uffdio_api.features after UFFDIO_API
	 *    succeeded.
	 *
	 * UFFD_FEATURE_MISSING_SHMEM works the same as
	 * UFFD_FEATURE_MISSING_HUGETLBFS, but it applies to shmem
	 * (i.e. tmpfs and other shmem based APIs).
	 *
	 * UFFD_FEATURE_SIGBUS feature means no page-fault
	 * (UFFD_EVENT_PAGEFAULT) event will be delivered, instead
	 * a SIGBUS signal will be sent to the faulting process.
	 *
	 * UFFD_FEATURE_THREAD_ID pid of the page faulted task_struct will
	 * be returned, if feature is not requested 0 will be returned.
	 *
	 * UFFD_FEATURE_MINOR_HUGETLBFS indicates that minor faults
	 * can be intercepted (via REGISTER_MODE_MINOR) for
	 * hugetlbfs-backed pages.
	 *
	 * UFFD_FEATURE_MINOR_SHMEM indicates the same support as
	 * UFFD_FEATURE_MINOR_HUGETLBFS, but for shmem-backed pages instead.
	 *
	 * UFFD_FEATURE_EXACT_ADDRESS indicates that the exact address of page
	 * faults would be provided and the offset within the page would not be
	 * masked.
	 *
	 * UFFD_FEATURE_WP_HUGETLBFS_SHMEM indicates that userfaultfd
	 * write-protection mode is supported on both shmem and hugetlbfs.
	 *
	 * UFFD_FEATURE_WP_UNPOPULATED indicates that userfaultfd
	 * write-protection mode will always apply to unpopulated pages
	 * (i.e. empty ptes).  This will be the default behavior for shmem
	 * & hugetlbfs, so this flag only affects anonymous memory behavior
	 * when userfault write-protection mode is registered.
	 *
	 * UFFD_FEATURE_WP_ASYNC indicates that userfaultfd write-protection
	 * asynchronous mode is supported in which the write fault is
	 * automatically resolved and write-protection is un-set.
	 * It implies UFFD_FEATURE_WP_UNPOPULATED.
	 *
	 * UFFD_FEATURE_MOVE indicates that the kernel supports moving an
	 * existing page contents from userspace.
	 */
	__u64 features;

	__u64 ioctls;
}

enum UFFD_FEATURE_PAGEFAULT_FLAG_WP = 1 << 0;
enum UFFD_FEATURE_EVENT_FORK = 1 << 1;
enum UFFD_FEATURE_EVENT_REMAP = 1 << 2;
enum UFFD_FEATURE_EVENT_REMOVE = 1 << 3;
enum UFFD_FEATURE_MISSING_HUGETLBFS = 1 << 4;
enum UFFD_FEATURE_MISSING_SHMEM = 1 << 5;
enum UFFD_FEATURE_EVENT_UNMAP = 1 << 6;
enum UFFD_FEATURE_SIGBUS = 1 << 7;
enum UFFD_FEATURE_THREAD_ID = 1 << 8;
enum UFFD_FEATURE_MINOR_HUGETLBFS = 1 << 9;
enum UFFD_FEATURE_MINOR_SHMEM = 1 << 10;
enum UFFD_FEATURE_EXACT_ADDRESS = 1 << 11;
enum UFFD_FEATURE_WP_HUGETLBFS_SHMEM = 1 << 12;
enum UFFD_FEATURE_WP_UNPOPULATED = 1 << 13;
enum UFFD_FEATURE_POISON = 1 << 14;
enum UFFD_FEATURE_WP_ASYNC = 1 << 15;
enum UFFD_FEATURE_MOVE = 1 << 16;

struct uffdio_range {
	__u64 start;
	__u64 len;
}

struct uffdio_register {
	uffdio_range range;
	__u64 mode;

	/*
	 * kernel answers which ioctl commands are available for the
	 * range, keep at the end as the last 8 bytes aren't read.
	 */
	__u64 ioctls;
}

enum UFFDIO_REGISTER_MODE_MISSING = ulong(1) << 0;
enum UFFDIO_REGISTER_MODE_WP = ulong(1) << 1;
enum UFFDIO_REGISTER_MODE_MINOR = ulong(1) << 2;

struct uffdio_copy {
	__u64 dst;
	__u64 src;
	__u64 len;
	/*
	 * UFFDIO_COPY_MODE_WP will map the page write protected on
	 * the fly.  UFFDIO_COPY_MODE_WP is available only if the
	 * write protected ioctl is implemented for the range
	 * according to the uffdio_register.ioctls.
	 */
	__u64 mode;

	/*
	 * "copy" is written by the ioctl and must be at the end: the
	 * copy_from_user will not read the last 8 bytes.
	 */
	__s64 copy;
}

enum UFFDIO_COPY_MODE_DONTWAKE = ulong(1) << 0;
enum UFFDIO_COPY_MODE_WP = ulong(1) << 1;

struct uffdio_zeropage {
	uffdio_range range;
	__u64 mode;

	/*
	 * "zeropage" is written by the ioctl and must be at the end:
	 * the copy_from_user will not read the last 8 bytes.
	 */
	__s64 zeropage;
}

enum UFFDIO_ZEROPAGE_MODE_DONTWAKE = ulong(1) < 0;

struct uffdio_writeprotect {
	uffdio_range range;
	/*
	 * UFFDIO_WRITEPROTECT_MODE_WP: set the flag to write protect a range,
	 * unset the flag to undo protection of a range which was previously
	 * write protected.
	 *
	 * UFFDIO_WRITEPROTECT_MODE_DONTWAKE: set the flag to avoid waking up
	 * any wait thread after the operation succeeds.
	 *
	 * NOTE: Write protecting a region (WP=1) is unrelated to page faults,
	 * therefore DONTWAKE flag is meaningless with WP=1.  Removing write
	 * protection (WP=0) in response to a page fault wakes the faulting
	 * task unless DONTWAKE is set.
	 */
	__u64 mode;
}

enum UFFDIO_WRITEPROTECT_MODE_WP = ulong(1) << 0;
enum UFFDIO_WRITEPROTECT_MODE_DONTWAKE = ulong(1) << 1;

struct uffdio_continue {
	uffdio_range range;
	/*
	 * UFFDIO_CONTINUE_MODE_WP will map the page write protected on
	 * the fly.  UFFDIO_CONTINUE_MODE_WP is available only if the
	 * write protected ioctl is implemented for the range
	 * according to the uffdio_register.ioctls.
	 */
	__u64 mode;

	/*
	 * Fields below here are written by the ioctl and must be at the end:
	 * the copy_from_user will not read past here.
	 */
	__s64 mapped;
}

enum UFFDIO_CONTINUE_MODE_DONTWAKE = ulong(1) << 0;
enum UFFDIO_CONTINUE_MODE_WP = ulong(1) << 1;

struct uffdio_poison {
	uffdio_range range;
	__u64 mode;

	/*
	 * Fields below here are written by the ioctl and must be at the end:
	 * the copy_from_user will not read past here.
	 */
	__s64 updated;
}

enum UFFDIO_POISON_MODE_DONTWAKE = ulong(1) << 0;

struct uffdio_move {
	__u64 dst;
	__u64 src;
	__u64 len;
	/*
	 * Especially if used to atomically remove memory from the
	 * address space the wake on the dst range is not needed.
	 */
	__u64 mode;
	/*
	 * "move" is written by the ioctl and must be at the end: the
	 * copy_from_user will not read the last 8 bytes.
	 */
	__s64 move;
}

enum UFFDIO_MOVE_MODE_DONTWAKE = ulong(1) << 0;
enum UFFDIO_MOVE_MODE_ALLOW_SRC_HOLES = ulong(1) << 1;

/*
 * Flags for the userfaultfd(2) system call itself.
 */

/*
 * Create a userfaultfd that can handle page faults only in user mode.
 */
enum UFFD_USER_MODE_ONLY = 1;
