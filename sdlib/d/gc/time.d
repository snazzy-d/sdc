module d.gc.time;

import core.stdc.time;

enum ulong Microsecond = 10;
enum ulong Millisecond = 1000 * Microsecond;
enum ulong Second = 1000 * Millisecond;
enum ulong Minute = 60 * Second;
enum ulong Hour = 60 * Minute;
enum ulong Day = 24 * Hour;
enum ulong Week = 7 * Day;

ulong getMonotonicTime() {
	timespec ts;
	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("clock_gettime failed!");
		exit(1);
	}

	// We convert the time to use 100ns as a base time unit.
	return (ts.tv_sec * Second) + (ts.tv_nsec / 100);
}
