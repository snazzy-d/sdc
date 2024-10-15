module sys.posix.types;

alias c_long = long;
alias c_ulong = ulong;

// Type of device numbers.
alias dev_t = ulong;
// Type of user identifications.
alias uid_t = uint;
// Type of group identifications.
alias gid_t = uint;
// Type of file serial numbers.
alias ino_t = __syscall_ulong_t;
// Type of file serial numbers (LFS).
alias ino64_t = ulong;
// Type of file attribute bitmasks.
alias mode_t = uint;
// Type of file link counts.
alias nlink_t = __syscall_ulong_t;
// Type of file sizes and offsets.
alias off_t = __syscall_slong_t;
// Type of file sizes and offsets (LFS).
alias off64_t = long;
// Type of process identifications.
alias pid_t = int;
// Type of file system IDs.
// TODO: fsid_t
// Type of CPU usage counts.
alias clock_t = __syscall_slong_t;
// Type for resource measurement.
alias rlim_t = __syscall_ulong_t;
// Type for resource measurement (LFS).
alias rlim64_t = ulong;
// General type for IDs.
alias id_t = uint;
// Seconds since the Epoch.
alias time_t = __syscall_slong_t;
// Count of microseconds.
alias useconds_t = uint;
// Signed count of microseconds.
alias suseconds_t = __syscall_slong_t;
alias suseconds64_t = long;

// The type of a disk address.
alias daddr_t = int;
// Type of an IPC key.
alias key_t = int;

// Clock ID used in clock and timer functions.
alias clockid_t = int;

// Timer ID returned by `timer_create'.
alias timer_t = void*;

// Type to represent block size.
alias blksize_t = __syscall_slong_t;

// Types from the Large File Support interface.

// Type to count number of disk blocks.
alias blkcnt_t = __syscall_slong_t;
alias blkcnt64_t = long;

// Type to count file system blocks.
alias fsblkcnt_t = __syscall_ulong_t;
alias fsblkcnt64_t = ulong;

// Type to count file system nodes.
alias fsfilcnt_t = __syscall_ulong_t;
alias fsfilcnt64_t = ulong;

// Type of miscellaneous file system fields.
alias fsword_t = __syscall_slong_t;

// Type of a byte count, or error.
alias ssize_t = c_long;

// Signed long type used in system calls.
alias __syscall_slong_t = c_long;
// Unsigned long type used in system calls.
alias __syscall_ulong_t = c_ulong;

/* These few don't really vary by system, they always correspond
   to one of the other defined types.  */
// Type of file sizes and offsets (LFS).
alias loff_t = off64_t;
alias caddr_t = char*;

/* C99: An integer type that can be accessed as an atomic entity,
   even in the presence of asynchronous interrupts.
   It is not currently necessary for this to be machine-specific.  */
alias sig_atomic_t = int;

/* Seconds since the Epoch, visible to user code when time_t is too
   narrow only for consistency with the old way of widening too-narrow
   types.  User code should never use time64_t.  */
alias time64_t = long;
