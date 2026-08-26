module core.stdc.sys.ioctl_;

import sys.posix.types;
import core.stdc.linux.ioctl;

extern(C):

/*
 * These are the most common definitions for tty ioctl numbers.
 * Most of them do not use the recommended _IOC(), but there is
 * probably some source code out there hardcoding the number,
 * so we might as well use them for all new platforms.
 *
 * The architectures that use different values here typically
 * try to be compatible with some Unix variants for the same
 * architecture.
 */

/* 0x54 is just a magic number to make these relatively unique ('T') */

enum TCGETS = 0x5401;
enum TCSETS = 0x5402;
enum TCSETSW = 0x5403;
enum TCSETSF = 0x5404;
enum TCGETA = 0x5405;
enum TCSETA = 0x5406;
enum TCSETAW = 0x5407;
enum TCSETAF = 0x5408;
enum TCSBRK = 0x5409;
enum TCXONC = 0x540A;
enum TCFLSH = 0x540B;
enum TIOCEXCL = 0x540C;
enum TIOCNXCL = 0x540D;
enum TIOCSCTTY = 0x540E;
enum TIOCGPGRP = 0x540F;
enum TIOCSPGRP = 0x5410;
enum TIOCOUTQ = 0x5411;
enum TIOCSTI = 0x5412;
enum TIOCGWINSZ = 0x5413;
enum TIOCSWINSZ = 0x5414;
enum TIOCMGET = 0x5415;
enum TIOCMBIS = 0x5416;
enum TIOCMBIC = 0x5417;
enum TIOCMSET = 0x5418;
enum TIOCGSOFTCAR = 0x5419;
enum TIOCSSOFTCAR = 0x541A;
enum FIONREAD = 0x541B;
enum TIOCINQ = FIONREAD;
enum TIOCLINUX = 0x541C;
enum TIOCCONS = 0x541D;
enum TIOCGSERIAL = 0x541E;
enum TIOCSSERIAL = 0x541F;
enum TIOCPKT = 0x5420;
enum FIONBIO = 0x5421;
enum TIOCNOTTY = 0x5422;
enum TIOCSETD = 0x5423;
enum TIOCGETD = 0x5424;
enum TCSBRKP = 0x5425; /* Needed for POSIX tcsendbreak() */
enum TIOCSBRK = 0x5427;/* BSD compatibility */
enum TIOCCBRK = 0x5428; /* BSD compatibility */
enum TIOCGSID = 0x5429; /* Return the session ID of FD */
// enum TCGETS2 = _IOR!('T', 0x2A, termios2);
// enum TCSETS2 = _IOW!('T', 0x2B, termios2);
// enum TCSETSW2 = _IOW!('T', 0x2C, termios2);
// enum TCSETSF2 = _IOW!('T', 0x2D, termios2);
enum TIOCGRS485 = 0x542E;
enum TIOCSRS485 = 0x542F;
enum TIOCGPTN = _IOR!('T', 0x30, uint);/* Get Pty Number (of pty-mux device) */
enum TIOCSPTLCK = _IOW!('T', 0x31, int); /* Lock/unlock Pty */
enum TIOCGDEV =
	_IOR!('T', 0x32, uint); /* Get primary device node of /dev/console */
enum TCGETX = 0x5432; /* SYS5 TCGETX compatibility */
enum TCSETX = 0x5433;
enum TCSETXF = 0x5434;
enum TCSETXW = 0x5435;
enum TIOCSIG = _IOW!('T', 0x36, int); /* pty: generate signal */
enum TIOCVHANGUP = 0x5437;
enum TIOCGPKT = _IOR!('T', 0x38, int); /* Get packet mode state */
enum TIOCGPTLCK = _IOR!('T', 0x39, int);/* Get Pty lock state */
enum TIOCGEXCL = _IOR!('T', 0x40, int); /* Get exclusive mode state */
enum TIOCGPTPEER = _IO!('T', 0x41); /* Safely open the slave */

// enum TIOCGISO7816 = _IOR!('T', 0x42, serial_iso7816);
// enum TIOCSISO7816 = _IOWR!('T', 0x43, serial_iso7816);

enum FIONCLEX = 0x5450;
enum FIOCLEX = 0x5451;
enum FIOASYNC = 0x5452;
enum TIOCSERCONFIG = 0x5453;
enum TIOCSERGWILD = 0x5454;
enum TIOCSERSWILD = 0x5455;
enum TIOCGLCKTRMIOS = 0x5456;
enum TIOCSLCKTRMIOS = 0x5457;
enum TIOCSERGSTRUCT = 0x5458;/* For debugging only */
enum TIOCSERGETLSR = 0x5459; /* Get line status register */
enum TIOCSERGETMULTI = 0x545A;/* Get multiport config  */
enum TIOCSERSETMULTI = 0x545B; /* Set multiport config */

enum TIOCMIWAIT = 0x545C; /* wait for a change on serial input line(s) */
enum TIOCGICOUNT = 0x545D; /* read serial port __inline__ interrupt counts */

/*
 * Some arches already define FIOQSIZE due to a historical
 * conflict with a Hayes modem-specific ioctl value.
 */
enum FIOQSIZE = 0x5460;

/* Used for packet mode */
enum TIOCPKT_DATA = 0;
enum TIOCPKT_FLUSHREAD = 1;
enum TIOCPKT_FLUSHWRITE = 2;
enum TIOCPKT_STOP = 4;
enum TIOCPKT_START = 8;
enum TIOCPKT_NOSTOP = 16;
enum TIOCPKT_DOSTOP = 32;
enum TIOCPKT_IOCTL = 64;

enum TIOCSER_TEMT = 0x01; /* Transmitter physically empty */

/* Define some types used by `ioctl' requests.  */

struct winsize {
	ushort ws_row;
	ushort ws_col;
	ushort ws_xpixel;
	ushort ws_ypixel;
}

/* modem lines */
enum TIOCM_LE = 0x001;
enum TIOCM_DTR = 0x002;
enum TIOCM_RTS = 0x004;
enum TIOCM_ST = 0x008;
enum TIOCM_SR = 0x010;
enum TIOCM_CTS = 0x020;
enum TIOCM_CAR = 0x040;
enum TIOCM_RNG = 0x080;
enum TIOCM_DSR = 0x100;
enum TIOCM_CD = TIOCM_CAR;
enum TIOCM_RI = TIOCM_RNG;

/* ioctl (fd, TIOCSERGETLSR, &result) where result may be as below */

/* line disciplines */
enum N_TTY = 0;
enum N_SLIP = 1;
enum N_MOUSE = 2;
enum N_PPP = 3;
enum N_STRIP = 4;
enum N_AX25 = 5;
enum N_X25 = 6; /* X.25 async  */
enum N_6PACK = 7;
enum N_MASC = 8;/* Mobitex module  */
enum N_R3964 = 9;/* Simatic R3964 module  */
enum N_PROFIBUS_FDL = 10; /* Profibus  */
enum N_IRDA = 11; /* Linux IR  */
enum N_SMSBLOCK = 12; /* SMS block mode  */
enum N_HDLC = 13; /* synchronous HDLC  */
enum N_SYNC_PPP = 14; /* synchronous PPP  */
enum N_HCI = 15; /* Bluetooth HCI UART  */

/* Perform the I/O control operation specified by REQUEST on FD.
   One argument may follow; its presence and type depend on REQUEST.
   Return value depends on REQUEST.  Usually -1 indicates error.  */
int ioctl(int __fd, c_ulong __request, ...);
