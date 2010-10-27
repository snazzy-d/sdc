/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module runner;

import std.conv;
import std.file;
import std.process;
import std.stdio;
import std.string;


version (Windows) {
    immutable SDC      = "sdc";  // Put SDC in your PATH.
    immutable EXE_NAME = "a.exe";
} else {
    immutable SDC      = "../sdc"; // Leaving this decision to the Unix crowd.
    immutable EXE_NAME = "a.out";
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

bool test(string filename)
{
    static void malformed() { stderr.writeln("Malformed test."); }
    
    bool expectedToCompile;
    int expectedRetval;
    
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
        if (set.length == 0) {
            malformed();
            return false;
        }
        auto var = set[0].idup;
        
        switch (var) {
        case "compiles":
            auto val = set[1].idup;
            expectedToCompile = getBool(val);
            break;
        case "retval":
            auto val = set[1].idup;
            expectedRetval = getInt(val);
            break;
        default:
            stderr.writeln("Bad command '" ~ var ~ "'.");
            return false;
        }
    }
    
    auto command = format(`%s -o=%s --optimise "%s"`, SDC, EXE_NAME, filename);
    
    auto retval = system(command);
    if (expectedToCompile && retval != 0) {
        stderr.writeln("Program expected to compile did not.");
        return false;
    }
    if (!expectedToCompile && retval == 0) {
        stderr.writeln("Program expected not to compile did.");
        return false;
    }
    
    system(EXE_NAME);
    
    if (retval != expectedRetval) {
        stderr.writeln("Retval was '" ~ to!string(retval) ~ "', expected '" ~ to!string(expectedRetval) ~ "'.");
        return false;
    }
    return true;
}

void main()
{
    int testNumber;
    auto testName = getTestFilename(testNumber);
    while (exists(testName)) {
        write(testName ~ ":");
        auto succeeded = test(testName);
        writeln(succeeded ? "SUCCEEDED" : "FAILED");
        testName = getTestFilename(++testNumber);
    }
}
