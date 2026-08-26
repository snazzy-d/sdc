module core.stdc.linux.ioctl;

import sys.posix.types;

extern(C):

/* ioctl command encoding: 32 bits total, command in lower 16 bits,
 * size of the parameter structure in the lower 14 bits of the
 * upper 16 bits.
 * Encoding the size of the parameter structure in the ioctl request
 * is useful for catching programs compiled with old versions
 * and to avoid overwriting user space outside the user buffer area.
 * The highest 2 bits are reserved for indicating the ``access mode''.
 * NOTE: This limits the max parameter size to 16kB -1 !
 */

/*
 * The following is for compatibility across the various Linux
 * platforms.  The generic ioctl numbering scheme doesn't really enforce
 * a type field.  De facto, however, the top 8 bits of the lower 16
 * bits are indeed used as a type field, so we might just as well make
 * this explicit here.  Please be sure to use the decoding macros
 * below from now on.
 */
enum _IOC_NRBITS = 8;
enum _IOC_TYPEBITS = 8;

/*
 * Let any architecture override either of the following before
 * including this file.
 */
enum _IOC_SIZEBITS = 14;
enum _IOC_DIRBITS = 2;

enum _IOC_NRMASK = (1 << _IOC_NRBITS) - 1;
enum _IOC_TYPEMASK = (1 << _IOC_TYPEBITS) - 1;
enum _IOC_SIZEMASK = (1 << _IOC_SIZEBITS) - 1;
enum _IOC_DIRMASK = (1 << _IOC_DIRBITS) - 1;

enum _IOC_NRSHIFT = 0;
enum _IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS;
enum _IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS;
enum _IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS;

/*
 * Direction bits, which any architecture can choose to override
 * before including this file.
 *
 * NOTE: _IOC_WRITE means userland is writing and kernel is
 * reading. _IOC_READ means userland is reading and kernel is writing.
 */
enum _IOC_NONE = 0U;
enum _IOC_WRITE = 1U;
enum _IOC_READ = 2U;

/**
 * asm-generic/ioctl.h contains various macros. D does not have macros,
 * so we use several parameterless templates instead.
 */
extern(D):

enum uint _IOC(uint dir, uint type, uint nr, uint size) = (dir << _IOC_DIRSHIFT)
	| (type << _IOC_TYPESHIFT) | (nr << _IOC_NRSHIFT)
	| (size << _IOC_SIZESHIFT);

enum uint _IOC_TYPECHECK(T) = T.sizeof;

/*
 * Used to create numbers.
 *
 * NOTE: _IOW means userland is writing and kernel is reading. _IOR
 * means userland is reading and kernel is writing.
 */
enum _IO(uint type, uint nr) = _IOC!(_IOC_NONE, type, nr, 0);
enum _IOR(uint type, uint nr, argtype) =
	_IOC!(_IOC_READ, type, nr, _IOC_TYPECHECK!argtype);
enum _IOW(uint type, uint nr, argtype) =
	_IOC!(_IOC_WRITE, type, nr, _IOC_TYPECHECK!argtype);
enum _IOWR(uint type, uint nr, argtype) =
	_IOC!(_IOC_READ | _IOC_WRITE, type, nr, _IOC_TYPECHECK!argtype);
enum _IOR_BAD(uint type, uint nr, argtype) =
	_IOC!(_IOC_READ, type, nr, argtype.sizeof);
enum _IOW_BAD(uint type, uint nr, argtype) =
	_IOC!(_IOC_WRITE, type, nr, argtype.sizeof);
enum _IOWR_BAD(uint type, uint nr, argtype) =
	_IOC!(_IOC_READ | _IOC_WRITE, type, nr, argtype.sizeof);

/* used to decode ioctl numbers.. */
enum _IOC_DIR(uint nr) = (nr >> _IOC_DIRSHIFT) & _IOC_DIRMASK;
enum _IOC_TYPE(uint nr) = (nr >> _IOC_TYPESHIFT) & _IOC_TYPEMASK;
enum _IOC_NR(uint nr) = (nr >> _IOC_NRSHIFT) & _IOC_NRMASK;
enum _IOC_SIZE(uint nr) = (nr >> _IOC_SIZESHIFT) & _IOC_SIZEMASK;

/* ...and for the drivers/sound files... */

enum IOC_IN = _IOC_WRITE << _IOC_DIRSHIFT;
enum IOC_OUT = _IOC_READ << _IOC_DIRSHIFT;
enum IOC_INOUT = (_IOC_WRITE | _IOC_READ) << _IOC_DIRSHIFT;
enum IOCSIZE_MASK = _IOC_SIZEMASK << _IOC_SIZESHIFT;
enum IOCSIZE_SHIFT = _IOC_SIZESHIFT;
