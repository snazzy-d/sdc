module core.stdc.fcntl;

import sys.posix.types;

extern(C):

enum O_ACCMODE = 0x03;
enum O_RDONLY = 0x00;
enum O_WRONLY = 0x01;
enum O_RDWR = 0x02;
enum O_CREAT = 0x40; // octal 0100
enum O_EXCL = 0x80; // octal 0200
enum O_NOCTTY = 0x100; // octal 0400
enum O_TRUNC = 0x200; // octal 01000
enum O_APPEND = 0x400; // octal 02000
enum O_NONBLOCK = 0x800; // octal 04000
enum O_NDELAY = O_NONBLOCK;
enum O_SYNC = 0x101000; // octal 04010000
enum O_FSYNC = O_SYNC;
enum O_ASYNC = 0x2000; // octal 020000
enum __O_LARGEFILE = 0x08000; // octal 0100000

enum __O_DIRECTORY = 0x010000; // octal 0200000
enum __O_NOFOLLOW = 0x020000; // octal 0400000
enum __O_CLOEXEC = 0x80000; // octal 02000000
enum __O_DIRECT = 0x004000; // octal 040000
enum __O_NOATIME = 0x40000; // octal 01000000
enum __O_PATH = 0x200000; // octal 010000000
enum __O_DSYNC = 0x1000; // octal 010000
enum __O_TMPFILE = 0x400000 | __O_DIRECTORY; // octal 020000000 | __O_DIRECTORY

// Must be a directory.
enum O_DIRECTORY = __O_DIRECTORY;

// Do not follow links.
enum O_NOFOLLOW = __O_NOFOLLOW;

// Set close_on_exec.
enum O_CLOEXEC = __O_CLOEXEC;

// Direct disk access.
enum O_DIRECT = __O_DIRECT;

// Do not set atime.
enum O_NOATIME = __O_NOATIME;

// Resolve pathname but do not open file.
enum O_PATH = __O_PATH;

// Atomically create nameless file.
enum O_TMPFILE = __O_TMPFILE;

// TODO: bits/fcntl-linux.h
// TODO: fnctl/fnctl64

int open(const char* __file, int __oflag, ...);
int openat(int __fd, const char* __file, int __oflag, ...);
int creat(const char* __file, mode_t __mode);

// TODO: lockf/lockf64
// TODO: posix_fadvise/posix_fadvise64
// TODO: posix_fallocate/posix_fallocate64
