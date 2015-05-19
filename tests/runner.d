#!/usr/bin/env rdmd
/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module runner;

import std.algorithm;
import std.concurrency;
import std.conv;
import std.file;
alias std.file file;
import std.getopt;
import std.process;
import std.range;
import std.stdio;
import std.string;
import core.stdc.stdlib;
version (linux) import core.sys.posix.unistd;


immutable SDC = "../bin/sdc";
immutable DMD = "dmd";

version (Windows) {
    immutable EXE_EXTENSION = ".exe";
} else {
    immutable EXE_EXTENSION = ".bin";
}


string getTestFilename(int n)
{
    return format("test%04s.d",n);
}

bool getBool(string s)
{
    return s == "yes";
}

int getInt(string s)
{
    return parse!int(s);
}

void test(string filename, string compiler)
{
    auto managerTid = receiveOnly!Tid();
    bool has = true;
    bool expectedToCompile = true;
    int expectedRetval = 0;
    string[] dependencies;
    
    assert(exists(filename));
    auto f = File(filename, "r");
    foreach (line; f.byLine) {
        if (line.length < 3 || line[0 .. 3] != "//T") {
            continue;
        }
        auto words = split(line);
        if (words.length != 2) {
            stderr.writefln("%s: malformed test.", filename);
            managerTid.send(filename, false, has);
            return;
        }
        auto set = split(words[1], ":");
        if (set.length < 2) {
            stderr.writefln("%s: malformed test.", filename);
            managerTid.send(filename, false, has);
            return;
        }
        auto var = set[0].idup;
        auto val = set[1].idup;
        
        switch (var) {
        case "compiles":
            expectedToCompile = getBool(val);
            break;
        case "retval":
            expectedRetval = getInt(val);
            break;
        case "dependency":
            dependencies ~= val;
            break;
        case "has-passed":
            has = getBool(val);
            break;
        default:
            stderr.writefln("%s: invalid command.", filename);
            managerTid.send(filename, false, has);
            return;
        }
    }
    f.close();
    
    string command;
    string cmdDeps = reduce!((string deps, string dep){ return format(`%s"%s" `, deps, dep); })("", dependencies);
    version (Windows) string exeName;
    else string exeName = "./";
    exeName ~= filename ~ EXE_EXTENSION;
    if (file.exists(exeName)) {
        file.remove(exeName);
    }
    if (compiler == SDC) {
        command = format(`%s -o %s "%s" %s`, SDC, exeName, filename, cmdDeps);
    } else if (compiler == DMD) {
            command = format(`%s -of%s "%s" %s`, compiler, exeName, filename, cmdDeps);
    } else { 
            command = format(`%s %s "%s" %s`, compiler, exeName, filename, cmdDeps);
    }

    // For some reasons &> is read as & > /dev/null causing the compiler to return 0.
    version (Posix) if(!expectedToCompile || true) command ~= " 2> /dev/null 1> /dev/null";
    
    auto retval = system(command);
    if (expectedToCompile && retval != 0) {
        stderr.writefln("%s: test expected to compile, did not.", filename);
        managerTid.send(filename, false, has);
        return;
    }
    if (!expectedToCompile && retval == 0) {
        stderr.writefln("%s: test expected to not compile, did.", filename);
        managerTid.send(filename, false, has);
        return;
    }
    if (!expectedToCompile && retval != 0) {
        managerTid.send(filename, true, has);
        return;
    }

    assert(expectedToCompile);
    command = exeName;
    version (Posix) command ~= " 2> /dev/null 1> /dev/null";

    retval = system(command);
    
    if (retval != expectedRetval) {
        stderr.writefln("%s: expected retval %s, got %s", filename, expectedRetval, retval);
        managerTid.send(filename, false, has);
        return;
    }

    managerTid.send(filename, true, has);
}

void main(string[] args)
{
    string compiler = SDC;
    version (linux) size_t jobCount = sysconf(_SC_NPROCESSORS_ONLN);
    else size_t jobCount = 1;
    bool displayOnlyFailed = false;
    bool waitOnExit = false;
    getopt(args,
            "compiler", &compiler,
            "j", &jobCount,
            "only-failed", &displayOnlyFailed,
            "wait-on-exit", &waitOnExit,
            "help", delegate {usage(); exit(0);});
    if (args.length > 1) {
        int testNumber = to!int(args[1]);
        auto testName = getTestFilename(testNumber);
        auto job = spawn(&test, testName, compiler);
        job.send(thisTid);

        auto result = receiveOnly!(string, bool, bool)();
        bool regressed = !result[1] & result[2];
        bool fixed = result[1] & !result[2];

        if (result[1]) {
            if (!displayOnlyFailed) writef("%s: %s", result[0], "SUCCEEDED");
        } else {
            writef("%s: %s", result[0], "FAILED");
        }

        if (fixed) {
            if (!displayOnlyFailed) writefln(", FIXED");
        } else if (regressed) {
            writeln(", REGRESSION");
        } else {
            writeln();
        }

        return;
    }

    // Figure out how many tests there are.
    int testNumber = -1;
    while (exists(getTestFilename(++testNumber))) {}
    if (testNumber < 0) {
        stderr.writeln("No tests found.");
        return;
    }
    
    auto tests = array( map!getTestFilename(iota(0, testNumber)) );

    size_t testIndex = 0;
    int passed = 0;
    int regressions = 0;
    int improvments = 0;
    while (testIndex < tests.length) {
        Tid[] jobs;
        // spawn $jobCount concurrent jobs. 
        while (jobs.length < jobCount && testIndex < tests.length) {
            jobs ~= spawn(&test, tests[testIndex], compiler);
            jobs[$ - 1].send(thisTid);
            testIndex++;
        }

        foreach (job; jobs) {
            auto testResult = receiveOnly!(string, bool, bool)();
            bool regressed = !testResult[1] & testResult[2];
            bool fixed = testResult[1] & !testResult[2];

            passed += testResult[1];
            regressions += regressed;
            improvments += fixed;
            if (testResult[1]) {
                if (!displayOnlyFailed) writef("%s: %s", testResult[0], "SUCCEEDED");
            } else {
                writef("%s: %s", testResult[0], "FAILED");
            }

            if (fixed) {
                if (!displayOnlyFailed) writefln(", FIXED");
            } else if (regressed) {
                writefln(", REGRESSION");
            } else {
                if ((displayOnlyFailed && !testResult[1]) || !displayOnlyFailed) {
                    writefln("");
                }
            }
        }
    }

    if (testNumber > 0) {
        writefln("Summary: %s tests, %s pass%s, %s failure%s, %.2f%% pass rate, "
                 "%s regressions, %s improvements.",
                 testNumber, passed, passed == 1 ? "" : "es", 
                 testNumber - passed, (testNumber - passed) == 1 ? "" : "s", 
                 (cast(real)passed / testNumber) * 100,
                 regressions, improvments);
    }
    
    if (waitOnExit) {
        write("Press any key to exit...");
        readln();
    }
}

/// Print usage to stdout.
void usage()
{
    writeln("runner [options] [specific test]");
    writeln("  run with no arguments to run test suite.");
    writeln("    --compiler:     which compiler to run.");
    writeln("    -j:             how many tests to do at once.");
    writeln("                    (on Linux this will automatically be number of processors)");
    writeln("    --only-failed:  only display failed tests.");
    writeln("    --wait-on-exit: wait for user input before exiting.");
    writeln("    --help:         display this message and exit.");
}
