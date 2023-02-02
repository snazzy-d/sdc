/**
 * D header file for GNU/Linux
 *
 * Authors: Martin Nowak
 */
module sys.linux.config;

version(linux):

// import sys.posix.config;
enum _XOPEN_SOURCE     = 600;

// man 7 feature_test_macros
// http://www.gnu.org/software/libc/manual/html_node/Feature-Test-Macros.html
enum _GNU_SOURCE = true;

enum _FILE_OFFSET_BITS   = 64;

// <sys/cdefs.h>
enum __REDIRECT          = false;
enum _REENTRANT          = true; // set by compiler when linking -pthread

// deduced <features.h>
// http://sourceware.org/git/?p=glibc.git;a=blob;f=include/features.h
enum _BSD_SOURCE = true;
enum _SVID_SOURCE = true;
enum _ATFILE_SOURCE = true;

enum __USE_FILE_OFFSET64 = _FILE_OFFSET_BITS == 64;
enum __USE_LARGEFILE     = __USE_FILE_OFFSET64 && !__REDIRECT;
enum __USE_LARGEFILE64   = __USE_FILE_OFFSET64 && !__REDIRECT;

enum __USE_XOPEN2K       = _XOPEN_SOURCE >= 600;
enum __USE_XOPEN2KXSI    = _XOPEN_SOURCE >= 600;
enum __USE_XOPEN2K8      = _XOPEN_SOURCE >= 700;
enum __USE_XOPEN2K8XSI   = _XOPEN_SOURCE >= 700;

enum __USE_MISC          = _BSD_SOURCE || _SVID_SOURCE;
enum __USE_BSD           = _BSD_SOURCE;
enum __USE_SVID          = _SVID_SOURCE;
enum __USE_ATFILE        = _ATFILE_SOURCE;
enum __USE_GNU           = _GNU_SOURCE;
enum __USE_REENTRANT     = _REENTRANT;

version(D_LP64)
	enum __WORDSIZE=64;
else
	enum __WORDSIZE=32;

