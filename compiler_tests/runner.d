/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module runner;

import std.conv;
import std.getopt;
import std.file;
import std.process;
import std.stdio;
import std.string;
import std.algorithm;


version (Windows) {
    immutable SDC      = "sdc";  // Put SDC in your PATH.
    immutable EXE_NAME = "a.exe";
} else {
    immutable SDC      = "../sdc"; // Leaving this decision to the Unix crowd.
    immutable EXE_NAME = "./a.out";
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

bool test(string filename, string compiler)
{
    static void malformed() { stderr.writeln("Malformed test."); }
    
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
            malformed();
            return false;
        }
        auto set = split(words[1], ":");
        if (set.length < 2) {
            malformed();
            return false;
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
            stderr.writeln("Bad command '" ~ var ~ "'.");
            return false;
        }
    }
    
    string command;
    string cmdDeps = reduce!((string deps, string dep){ return format(`%s"%s" `, deps, dep); })("", dependencies);
    if (compiler == SDC) {
        command = format(`%s -o=%s --optimise "%s" %s`, SDC, EXE_NAME, filename, cmdDeps);
    } else {
        command = format(`%s "%s" %s`, compiler, filename, cmdDeps);
    }
    
    
    auto retval = system(command);
    if (expectedToCompile && retval != 0) {
        stderr.writeln("Program expected to compile did not.");
        return false;
    }
    if (!expectedToCompile && retval == 0) {
        stderr.writeln("Program expected not to compile did.");
        return false;
    }
    
    retval = system(EXE_NAME);
    
    if (retval != expectedRetval  && expectedToCompile) {
        stderr.writeln("Retval was '" ~ to!string(retval) ~ "', expected '" ~ to!string(expectedRetval) ~ "'.");
        return false;
    }
    return true;
}

void main(string[] args)
{
    string compiler = SDC;
    getopt(args, "compiler", &compiler);
    if (args.length > 1) {
        int testNumber = to!int(args[1]);
        auto testName = getTestFilename(testNumber);
        writeln(test(testName, compiler) ? "SUCCEEDED" : "FAILED");
        return;
    }
	
    int testNumber = 0;
    auto testName = getTestFilename(testNumber);
    int  passed = 0;
    while (exists(testName)) {
        write(testName ~ ":");
        auto succeeded = test(testName, compiler);
        passed = passed + (succeeded ? 1 : 0);
        writeln(succeeded ? "SUCCEEDED" : "FAILED");
        testName = getTestFilename(++testNumber);
    }
    assert(passed <= testNumber);
    if (testNumber > 0) {
        writefln("Summary: %s tests, %s pass%s, %s failure%s, %.2f%% pass rate",
                 testNumber, passed, passed == 1 ? "" : "es", 
                 testNumber - passed, (testNumber - passed) == 1 ? "" : "s", 
                 (cast(real)passed / testNumber) * 100);
    }
}
