#!/usr/bin/env -S sh -c 'rdmd -I`dirname "$0"` "$0" "$@"'
/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 */
module runner;

import util;

immutable SDC = "bin/sdc";

immutable EXE_EXTENSION = ".bin";

// A test that takes longer than this is assumed to never finish.
enum Timeout = 300;

struct ExecuteResult {
	int status;
	string output;
	bool timedOut;
}

/**
 * Execute the command, and kill it if it does not finish in time, so that a
 * test that never finishes fails instead of blocking the run.
 */
ExecuteResult executeWithTimeout(string[] command, string dir) {
	import std.process, std.stdio;
	auto output = File.tmpfile();
	// Keep the output open to read it once the process is done.
	auto config = Config.retainStdout | Config.retainStderr;
	auto pid = spawnProcess(command, stdin, output, output, /* env = */ null,
	                        config, dir);

	import core.thread, core.time;
	auto deadline = MonoTime.currTime + Timeout.seconds;

	ExecuteResult result;
	while (true) {
		auto r = tryWait(pid);
		if (r.terminated) {
			result.status = r.status;
			break;
		}

		if (MonoTime.currTime >= deadline) {
			kill(pid);
			result.status = wait(pid);
			result.timedOut = true;
			break;
		}

		Thread.sleep(10.msecs);
	}

	output.rewind();

	import std.array;
	auto content = appender!string();
	foreach (chunk; output.byChunk(4096)) {
		content ~= cast(const(char)[]) chunk;
	}

	result.output = content.data;
	return result;
}

string getTestFilename(int n) {
	import std.format;
	return format("test/legacy/test%04s.d", n);
}

enum Mode {
	Legacy,
	Invalid,
}

struct Task {
	string name;
	string compiler;
	Mode mode;

	TestResult run() {
		bool hasPassed = true;
		int expectedRetval = 0;
		string[] dependencies;
		string[] errors;

		bool expectedToCompile;

		final switch (mode) with (Mode) {
			case Legacy:
				expectedToCompile = true;
				break;

			case Invalid:
				expectedToCompile = false;
				break;
		}

		import std.stdio;
		foreach (const(char)[] line; File(name, "r").byLine) {
			if (line.length < 3 || line[0 .. 3] != "//T") {
				continue;
			}

			import std.algorithm : findSplitAfter;
			auto parts = findSplitAfter(line[3 .. $], ":");

			import std.string;
			auto var = strip(parts[0][0 .. $ - 1]);
			auto val = strip(parts[1]).idup;

			if (var == "") {
				stderr.writefln("%s: malformed test.", name);
				return TestResult(name, false, hasPassed);
			}

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
					hasPassed = getBool(val);
					break;

				case "error":
					errors ~= val;
					break;

				default:
					stderr.writefln("%s: invalid command.", name);
					return TestResult(name, false, hasPassed);
			}
		}

		import std.path, std.file;
		auto dir = dirName(name);
		auto file = baseName(name);

		string exeName = file ~ EXE_EXTENSION;
		string fullExeName = dir ~ "/" ~ exeName;
		scope(exit) {
			if (exists(fullExeName)) {
				remove(fullExeName);
			}
		}

		string[] command = [compiler, "-o", exeName, file] ~ dependencies;

		auto result = executeWithTimeout(command, dir);
		if (result.timedOut) {
			stderr.writefln("%s: compilation timed out.", name);
			return TestResult(name, false, hasPassed);
		}

		string output = result.output;
		foreach (e; errors) {
			import std.algorithm : findSkip;
			if (!output.findSkip(e)) {
				stderr.writefln("%s: test expected error %s %s", name, [e],
				                [output]);
				return TestResult(name, false, hasPassed);
			}
		}

		if (expectedToCompile && result.status != 0) {
			stderr.writefln("%s: test expected to compile, did not (%d).", name,
			                result.status);
			return TestResult(name, false, hasPassed);
		}

		if (!expectedToCompile && result.status == 0) {
			stderr.writefln("%s: test expected to not compile, did.", name);
			return TestResult(name, false, hasPassed);
		}

		if (!expectedToCompile && result.status != 0) {
			return TestResult(name, true, hasPassed);
		}

		assert(expectedToCompile);
		if (!exists(fullExeName)) {
			stderr.writefln("%s: expected %s to be generated, but it wasn't",
			                name, exeName);
			return TestResult(name, false, hasPassed);
		}

		auto run = executeWithTimeout(["./" ~ exeName], dir);
		if (run.timedOut) {
			stderr.writefln("%s: execution timed out.", name);
			return TestResult(name, false, hasPassed);
		}

		auto retval = run.status;
		if (retval != expectedRetval) {
			stderr.writefln("%s: expected reval %s, got %s", name,
			                expectedRetval, retval);
			return TestResult(name, false, hasPassed);
		}

		return TestResult(name, true, hasPassed);
	}
}

struct TestRunner {
	enum Name = "Integration Test Runner";
	enum XtraDoc = "specific test";

	import std.meta;
	alias ExtraArgs =
		AliasSeq!("compiler", "The compiler executable to use.", string);

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
			while (exists(getTestFilename(testNumber))) {
				testNumber++;
			}

			import std.exception;
			enforce(testNumber > 0, "No tests found.");

			tests = iota(0, testNumber).map!getTestFilename().array();
		}

		auto legacy_tests = tests.map!(t => Task(t, compiler, Mode.Legacy));

		import std.file;
		tests = [];
		foreach (f; dirEntries("test/invalid", "*.d", SpanMode.breadth)) {
			if (!f.isFile()) {
				continue;
			}

			tests ~= f;
		}

		auto invalid_tests = tests.map!(t => Task(t, compiler, Mode.Invalid));

		return chain(legacy_tests, invalid_tests);
	}
}

int main(string[] args) {
	return runUtility(TestRunner(), args);
}
