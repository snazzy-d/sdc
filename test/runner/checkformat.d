#!/usr/bin/env rdmd
/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 */
module checkformat;

import std.algorithm;
import std.concurrency;
import std.conv;
import std.file;
alias std.file file;
import std.getopt;
import std.range;
import std.stdio;
import std.string;
import core.stdc.stdlib;
version (linux) import core.sys.posix.unistd;

immutable SDFMT = "../../bin/sdfmt";

string getTestFilename(int n) {
	return format("test%04s.d",n);
}

void test(string filename, string formatter) in {
	assert(exists(filename));
} body {
	auto managerTid = receiveOnly!Tid();
	
	string original = readText(filename);
	
	import std.process;
	auto result = execute([formatter, filename]);
	if (result.status != 0) {
		stderr.writefln("%s: sdfmt expected to format, did not (%d).", filename, result.status);
		managerTid.send(filename, false);
		return;
	}

	if (result.output != original) {
		stderr.writefln("%s: sdfmt did not format as expected.", filename);
		managerTid.send(filename, false);
		return;
	}
	
	managerTid.send(filename, true);
}

int main(string[] args) {
	string formatter = SDFMT;
	version (linux) size_t jobCount = sysconf(_SC_NPROCESSORS_ONLN);
	else size_t jobCount = 1;
	bool displayOnlyFailed = false;
	bool waitOnExit = false;
	getopt(
		args,
		"formatter", &formatter,
		"j", &jobCount,
		"only-failed", &displayOnlyFailed,
		"wait-on-exit", &waitOnExit,
		"help", delegate {usage(); exit(0);},
	);
	
	string[] tests;
	
	if (args.length > 1) {
		tests = args[1 .. $].map!(a => getTestFilename(to!int(a))).array();
	} else {
		// Figure out how many tests there are.
		int testNumber = -1;
		while (exists(getTestFilename(++testNumber))) {
			if (testNumber > 82) {
				break;
			}
		}
		if (testNumber < 0) {
			stderr.writeln("No tests found.");
			return -1;
		}
		
		tests = iota(0, testNumber).map!getTestFilename().array();
	}
	
	size_t testIndex = 0;
	int passed = 0;
	while (testIndex < tests.length) {
		Tid[] jobs;
		// spawn $jobCount concurrent jobs.
		while (jobs.length < jobCount && testIndex < tests.length) {
			jobs ~= spawn(&test, tests[testIndex], formatter);
			jobs[$ - 1].send(thisTid);
			testIndex++;
		}
		
		foreach (job; jobs) {
			auto testResult = receiveOnly!(string, bool)();

			passed += testResult[1];
			if (testResult[1]) {
				if (!displayOnlyFailed) {
					writef("%s: %s", testResult[0], "SUCCEEDED");
				}
			} else {
				writef("%s: %s", testResult[0], "FAILED");
			}

			if ((displayOnlyFailed && !testResult[1]) || !displayOnlyFailed) {
				writefln("");
			}
		}
	}

	if (tests.length > 0) {
		writefln("Summary: %s tests, %s pass%s, %s failure%s, %.2f%% pass rate.",
				 tests.length, passed, passed == 1 ? "" : "es",
				 tests.length - passed, (tests.length - passed) == 1 ? "" : "s",
				 (cast(real)passed / tests.length) * 100);
	}
	
	if (waitOnExit) {
		write("Press any key to exit...");
		readln();
	}

	return passed != tests.length ? -1 : 0;
}

/// Print usage to stdout.
void usage() {
	writeln("checkformat [options] [specific test]");
	writeln("  run with no arguments to run test suite.");
	writeln("    --formatter:    which formatter to run.");
	writeln("    -j:             how many tests to do at once.");
	writeln("                    (on Linux this will automatically be number of processors)");
	writeln("    --only-failed:  only display failed tests.");
	writeln("    --wait-on-exit: wait for user input before exiting.");
	writeln("    --help:         display this message and exit.");
}
