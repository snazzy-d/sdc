module core.stdc.time;

import sys.posix.types;

extern(C):

enum clock_t CLOCKS_PER_SEC = 1000000;

// Identifier for system-wide realtime clock.
enum CLOCK_REALTIME = 0;
// Monotonic system-wide clock.
enum CLOCK_MONOTONIC = 1;
// High-resolution timer from the CPU.
enum CLOCK_PROCESS_CPUTIME_ID = 2;
// Thread-specific CPU-time clock.
enum CLOCK_THREAD_CPUTIME_ID = 3;
// Monotonic system-wide clock, not adjusted for frequency scaling.
enum CLOCK_MONOTONIC_RAW = 4;
// Identifier for system-wide realtime clock, updated only on ticks.
enum CLOCK_REALTIME_COARSE = 5;
// Monotonic system-wide clock, updated only on ticks.
enum CLOCK_MONOTONIC_COARSE = 6;
// Monotonic system-wide clock that includes time spent in suspension.
enum CLOCK_BOOTTIME = 7;
// Like CLOCK_REALTIME but also wakes suspended system.
enum CLOCK_REALTIME_ALARM = 8;
// Like CLOCK_BOOTTIME but also wakes suspended system.
enum CLOCK_BOOTTIME_ALARM = 9;
// Like CLOCK_REALTIME but in International Atomic Time.
enum CLOCK_TAI = 11;

// Flag to indicate time is absolute.
enum TIMER_ABSTIME = 1;

// TODO: timex, clock_adjtime

struct tm {
	// Seconds.     [0-60] (1 leap second)
	int tm_sec;
	// Minutes.     [0-59]
	int tm_min;
	// Hours.       [0-23]
	int tm_hour;
	// Day.         [1-31]
	int tm_mday;
	// Month.       [0-11]
	int tm_mon;
	// Year - 1900.
	int tm_year;
	// Day of week. [0-6]
	int tm_wday;
	// Days in year.[0-365]
	int tm_yday;
	// DST.         [-1/0/1]
	int tm_isdst;

	// Seconds east of UTC.
	c_long tm_gmtoff;
	// Timezone abbreviation.
	const char* tm_zone;
}

struct timespec {
	// Seconds.
	time_t tv_sec;

	// XXX: Not sure what the right type is here,
	//      C headers are very confusing on that one.
	// Nanoseconds.
	__syscall_slong_t tv_nsec;
}

struct itimerspec {
	timespec it_interval;
	timespec it_value;
}

clock_t clock();

// Complains about redefinition of the module name.
// time_t time(time_t* __timer);

double difftime(time_t __time1, time_t __time0);

time_t mktime(tm* __tp);

// TODO: strftime, strptime, strftime_l, strptime_l

tm* gmtime(const time_t* __timer);
tm* localtime(const time_t* __timer);

// TODO: gmtime_r, localtime_r
// TODO: asctime, ctime
// TODO: asctime_r, ctime_r

void tzset();

// TODO: timegm, timelocal, dysize

int nanosleep(const timespec* __requested_time, timespec* __remaining);

int clock_getres(clockid_t __clock_id, timespec* __res);
int clock_gettime(clockid_t __clock_id, timespec* __tp);
int clock_settime(clockid_t __clock_id, const timespec* __tp);
int clock_nanosleep(clockid_t __clock_id, int __flags, const timespec* __req,
                    timespec* __rem);
int clock_getcpuclockid(pid_t __pid, clockid_t* __clock_id);

int timer_create(clockid_t __clock_id, sigevent* __evp, timer_t* __timerid);
int timer_delete(timer_t __timerid);
int timer_settime(timer_t __timerid, int __flags, const itimerspec* __value,
                  itimerspec* __ovalue);
int timer_gettime(timer_t __timerid, itimerspec* __value);
int timer_getoverrun(timer_t __timerid);

int timespec_get(timespec* __ts, int __base);
int timespec_getres(timespec* __ts, int __base);

tm* getdate(const char* __string);
int getdate_r(const char* __string, tm* __resbufp);
