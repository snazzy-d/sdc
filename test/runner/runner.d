#!/usr/bin/env -S sh -c 'rdmd -I`dirname "$0"` "$0" "$@"'
/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 */
module runner;

import util;

immutable SDC = "bin/sdc";

immutable EXE_EXTENSION = ".bin";

string getTestFilename(int n) {
	import std.format;
	return format("test%04s.d",n);
}

struct Task {
	string name;
	string compiler;
	
	TestResult run() {
		bool has = true;
		bool expectedToCompile = true;
		int expectedRetval = 0;
		string[] dependencies;
		
		import std.stdio, std.string;
		foreach (line; File("test/runner/" ~ name, "r").byLine) {
			if (line.length < 3 || line[0 .. 3] != "//T") {
				continue;
			}
			auto words = split(line);
			if (words.length != 2) {
				stderr.writefln("%s: malformed test.", name);
				return TestResult(name, false, has);
			}
			auto set = split(words[1], ":");
			if (set.length < 2) {
				stderr.writefln("%s: malformed test.", name);
				return TestResult(name, false, has);
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
				stderr.writefln("%s: invalid command.", name);
				return TestResult(name, false, has);
			}
		}

		string exeName = name ~ EXE_EXTENSION;
		scope(exit) {
			import std.file;
			if (exists(exeName)) {
				remove(exeName);
			}
		}
		
		import std.process;
		string[] command = [compiler, "-o", exeName, name] ~ dependencies;
		auto result = execute(command, /* env = */ null, Config.none, /* maxOutput = */ size_t.max, "test/runner");
		
		if (expectedToCompile && result.status != 0) {
			stderr.writefln("%s: test expected to compile, did not (%d).", name, result.status);
			return TestResult(name, false, has);
		}
		
		if (!expectedToCompile && result.status == 0) {
			stderr.writefln("%s: test expected to not compile, did.", name);
			return TestResult(name, false, has);
		}

		if (!expectedToCompile && result.status != 0) {
			return TestResult(name, true, has);
		}
		
		assert(expectedToCompile);
		auto retval = execute(["./" ~ exeName], /* env = */ null, Config.none, /* maxOutput = */ size_t.max, "test/runner").status;
		if (retval != expectedRetval) {
			stderr.writefln("%s: expected reval %s, got %s", name, expectedRetval, retval);
			return TestResult(name, false, has);
		}
		
		return TestResult(name, true, has);
	}
}

struct TestRunner {
	enum Name = "Integration Test Runner";
	enum XtraDoc = "specific test";
	
	import std.meta;
	alias ExtraArgs = AliasSeq!("compiler", "The compiler executable to use.", string);
	
	string compiler;
	
	void processArgs(string compiler) {
		this.compiler = getAbsolutePath(compiler);
	}
	
	auto getTasks(string[] args) {
		if (compiler == "") {
			compiler = getAbsolutePath(SDC);
		}
		
		string[] tests;
		
		import std.algorithm, std.range;
		if (args.length > 1) {
			tests = args[1 .. $].map!(a => getTestFilename(getInt(a))).array();
		} else {
			// Figure out how many tests there are.
			uint testNumber = 0;
			import std.file;
			while (exists("test/runner/" ~ getTestFilename(testNumber))) {
				testNumber++;
			}
			
			import std.exception;
			enforce(testNumber > 0, "No tests found.");
			
			tests = iota(0, testNumber - 1).map!getTestFilename().array();
		}
		
		return tests.map!(t => Task(t, compiler));
	}
}

int main(string[] args) {
	return runUtility(TestRunner(), args);
}
