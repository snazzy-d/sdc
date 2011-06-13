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
version (linux) import core.sys.posix.unistd;


version (Windows) {
    immutable SDC      = "sdc";  // Put SDC in your PATH.
    immutable EXE_EXTENSION = ".exe";
} else {
    immutable SDC      = "../sdc"; // Leaving this decision to the Unix crowd.
    immutable EXE_EXTENSION = ".bin";
}


string getTestFilename(int n)
{
    return "test" ~ to!string(n) ~ ".d";
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
            managerTid.send(filename, false);
            return;
        }
        auto set = split(words[1], ":");
        if (set.length < 2) {
            stderr.writefln("%s: malformed test.", filename);
            managerTid.send(filename, false);
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
        default:
            stderr.writefln("%s: invalid command.", filename);
            managerTid.send(filename, false);
            return;
        }
    }
    
    string command;
    string cmdDeps = reduce!((string deps, string dep){ return format(`%s"%s" `, deps, dep); })("", dependencies);
    version (Windows) string exeName;
    else string exeName = "./";
    exeName ~= filename ~ EXE_EXTENSION;
    if (file.exists(exeName)) {
        file.remove(exeName);
    }
    if (compiler == SDC) {
        command = format(`%s -o=%s --optimise "%s" %s`, SDC, exeName, filename, cmdDeps);
    } else {
        command = format(`%s%s "%s" %s`, compiler, exeName, filename, cmdDeps);
    }
    version (linux) if (!expectedToCompile) command ~= " &>/dev/null";
    
    
    auto retval = system(command);
    if (expectedToCompile && retval != 0) {
        stderr.writefln("%s: test expected to compile, did not.", filename);
        managerTid.send(filename, false);
        return;
    }
    if (!expectedToCompile && retval == 0) {
        stderr.writefln("%s: test expected to not compile, did.", filename);
        managerTid.send(filename, false);
        return;
    }
    if (!expectedToCompile && retval != 0) {
        managerTid.send(filename, true);
        return;
    }
    
    retval = system(exeName);
    
    if (retval != expectedRetval && expectedToCompile) {
        stderr.writefln("%s: expected retval %s, got %s", filename, expectedRetval, retval);
        managerTid.send(filename, false);
        return;
    }

    managerTid.send(filename, true);
}

void main(string[] args)
{
    string compiler = SDC;
    version (linux) size_t jobCount = sysconf(_SC_NPROCESSORS_ONLN);
    else size_t jobCount = 1;
    bool displayOnlyFailed = false;
    getopt(args, "compiler", &compiler, "j", &jobCount, "only-failed", &displayOnlyFailed);
    if (args.length > 1) {
        int testNumber = to!int(args[1]);
        auto testName = getTestFilename(testNumber);
        auto job = spawn(&test, testName, compiler);
        job.send(thisTid);
        auto result = receiveOnly!(string, bool)();
        if (!result[1] || !displayOnlyFailed) writeln(result[0], result[1] ? ": SUCCEEDED" : ": FAILED");
        return;
    }

    // Figure out how many tests there are.
    int testNumber = -1;
    while (exists(getTestFilename(++testNumber))) {}
    if (testNumber < 0) {
        stderr.writeln("No tests found.");
        return;
    }
    
    const tests = array( map!getTestFilename(iota(0, testNumber)) );

    size_t testIndex = 0;
    int passed = 0;
    while (testIndex < tests.length) {
        Tid[] jobs;
        // spawn $jobCount concurrent jobs. 
        while (jobs.length < jobCount && testIndex < tests.length) {
            jobs ~= spawn(&test, tests[testIndex], compiler);
            jobs[$ - 1].send(thisTid);
            testIndex++;
        }

        foreach (job; jobs) {
            auto testResult = receiveOnly!(string, bool)();
            passed = passed + testResult[1];
            if (testResult[1]) {
                if (!displayOnlyFailed) writeln(testResult[0], ": SUCCEEDED");
            } else {
                writeln(testResult[0], ": FAILED");
            }
        }
    }

    if (testNumber > 0) {
        writefln("Summary: %s tests, %s pass%s, %s failure%s, %.2f%% pass rate",
                 testNumber, passed, passed == 1 ? "" : "es", 
                 testNumber - passed, (testNumber - passed) == 1 ? "" : "s", 
                 (cast(real)passed / testNumber) * 100);
    }
}
