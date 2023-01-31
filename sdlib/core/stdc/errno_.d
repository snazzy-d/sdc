// FIXME: This should be named errno, but SDC think this
// conflicts with alias errno declared in the module.
module core.stdc.errno_;

version(Posix):
extern(C):

version(linux) {
	@property
	ref int __errno_location();
	alias errno = __errno_location;

	enum EPERM              = 1;
	enum ENOENT             = 2;
	enum ESRCH              = 3;
	enum EINTR              = 4;
	enum EIO                = 5;
	enum ENXIO              = 6;
	enum E2BIG              = 7;
	enum ENOEXEC            = 8;
	enum EBADF              = 9;
	enum ECHILD             = 10;
	enum EAGAIN             = 11;
	enum ENOMEM             = 12;
	enum EACCES             = 13;
	enum EFAULT             = 14;
	enum ENOTBLK            = 15;
	enum EBUSY              = 16;
	enum EEXIST             = 17;
	enum EXDEV              = 18;
	enum ENODEV             = 19;
	enum ENOTDIR            = 20;
	enum EISDIR             = 21;
	enum EINVAL             = 22;
	enum ENFILE             = 23;
	enum EMFILE             = 24;
	enum ENOTTY             = 25;
	enum ETXTBSY            = 26;
	enum EFBIG              = 27;
	enum ENOSPC             = 28;
	enum ESPIPE             = 29;
	enum EROFS              = 30;
	enum EMLINK             = 31;
	enum EPIPE              = 32;
	enum EDOM               = 33;
	enum ERANGE             = 34;

	version(X86_64) {
		enum EDEADLK            = 35;
		enum ENAMETOOLONG       = 36;
		enum ENOLCK             = 37;
		enum ENOSYS             = 38;
		enum ENOTEMPTY          = 39;
		enum ELOOP              = 40;
		enum EWOULDBLOCK        = EAGAIN;
		enum ENOMSG             = 42;
		enum EIDRM              = 43;
		enum ECHRNG             = 44;
		enum EL2NSYNC           = 45;
		enum EL3HLT             = 46;
		enum EL3RST             = 47;
		enum ELNRNG             = 48;
		enum EUNATCH            = 49;
		enum ENOCSI             = 50;
		enum EL2HLT             = 51;
		enum EBADE              = 52;
		enum EBADR              = 53;
		enum EXFULL             = 54;
		enum ENOANO             = 55;
		enum EBADRQC            = 56;
		enum EBADSLT            = 57;
		enum EDEADLOCK          = EDEADLK;
		enum EBFONT             = 59;
		enum ENOSTR             = 60;
		enum ENODATA            = 61;
		enum ETIME              = 62;
		enum ENOSR              = 63;
		enum ENONET             = 64;
		enum ENOPKG             = 65;
		enum EREMOTE            = 66;
		enum ENOLINK            = 67;
		enum EADV               = 68;
		enum ESRMNT             = 69;
		enum ECOMM              = 70;
		enum EPROTO             = 71;
		enum EMULTIHOP          = 72;
		enum EDOTDOT            = 73;
		enum EBADMSG            = 74;
		enum EOVERFLOW          = 75;
		enum ENOTUNIQ           = 76;
		enum EBADFD             = 77;
		enum EREMCHG            = 78;
		enum ELIBACC            = 79;
		enum ELIBBAD            = 80;
		enum ELIBSCN            = 81;
		enum ELIBMAX            = 82;
		enum ELIBEXEC           = 83;
		enum EILSEQ             = 84;
		enum ERESTART           = 85;
		enum ESTRPIPE           = 86;
		enum EUSERS             = 87;
		enum ENOTSOCK           = 88;
		enum EDESTADDRREQ       = 89;
		enum EMSGSIZE           = 90;
		enum EPROTOTYPE         = 91;
		enum ENOPROTOOPT        = 92;
		enum EPROTONOSUPPORT    = 93;
		enum ESOCKTNOSUPPORT    = 94;
		enum EOPNOTSUPP         = 95;
		enum ENOTSUP            = EOPNOTSUPP;
		enum EPFNOSUPPORT       = 96;
		enum EAFNOSUPPORT       = 97;
		enum EADDRINUSE         = 98;
		enum EADDRNOTAVAIL      = 99;
		enum ENETDOWN           = 100;
		enum ENETUNREACH        = 101;
		enum ENETRESET          = 102;
		enum ECONNABORTED       = 103;
		enum ECONNRESET         = 104;
		enum ENOBUFS            = 105;
		enum EISCONN            = 106;
		enum ENOTCONN           = 107;
		enum ESHUTDOWN          = 108;
		enum ETOOMANYREFS       = 109;
		enum ETIMEDOUT          = 110;
		enum ECONNREFUSED       = 111;
		enum EHOSTDOWN          = 112;
		enum EHOSTUNREACH       = 113;
		enum EALREADY           = 114;
		enum EINPROGRESS        = 115;
		enum ESTALE             = 116;
		enum EUCLEAN            = 117;
		enum ENOTNAM            = 118;
		enum ENAVAIL            = 119;
		enum EISNAM             = 120;
		enum EREMOTEIO          = 121;
		enum EDQUOT             = 122;
		enum ENOMEDIUM          = 123;
		enum EMEDIUMTYPE        = 124;
		enum ECANCELED          = 125;
		enum ENOKEY             = 126;
		enum EKEYEXPIRED        = 127;
		enum EKEYREVOKED        = 128;
		enum EKEYREJECTED       = 129;
		enum EOWNERDEAD         = 130;
		enum ENOTRECOVERABLE    = 131;
		enum ERFKILL            = 132;
		enum EHWPOISON          = 133;
	}
} else version(OSX) {
	@property
	ref int __error();
	alias errno = __error;
}
