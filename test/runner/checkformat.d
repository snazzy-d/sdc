#!/usr/bin/env -S sh -c 'rdmd -I`dirname "$0"` "$0" "$@"'
/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 */
module checkformat;

import util;

immutable SDFMT = "bin/sdfmt";

string getTestFilename(int n) {
	import std.format;
	return format("test/runner/test%04s.d",n);
}

struct Task {
	string name;
	string formatter;
	
	TestResult run() {
		import std.file;
		string original = cast(string) read(name);
		
		import std.process;
		auto result = execute([formatter, name]);
		
		import std.stdio;
		if (result.status != 0) {
			stderr.writefln("%s: sdfmt expected to format, did not (%d).", name, result.status);
			return TestResult(name, false, true);
		}
		
		import std.encoding;
		auto bom = getBOM(cast(const(ubyte)[]) original).schema;
		if (bom == BOM.none && result.output != original) {
			stderr.writefln("%s: sdfmt did not format as expected.", name);
			return TestResult(name, false, true);
		}
		
		return TestResult(name, true, true);
	}
}

struct CheckFormat {
	enum Name = "Formatter Test Runner";
	enum XtraDoc = "specific test";
	
	import std.meta;
	alias ExtraArgs = AliasSeq!("formatter", "The formatter executable to use.", string);
	
	string formatter;
	
	void processArgs(string formatter) {
		this.formatter = getAbsolutePath(formatter);
	}
	
	auto getTasks(string[] args) {
		if (formatter == "") {
			formatter = getAbsolutePath(SDFMT);
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
			
			tests = iota(0, testNumber - 1).map!getTestFilename().array();
		}
		
		import std.file;
		foreach (f; dirEntries("test/invalid", "*.d", SpanMode.breadth)) {
			if (!f.isFile()) {
				continue;
			}
			
			tests ~= f;
		}
		
		return tests.map!(t => Task(t, formatter));
	}
}

int main(string[] args) {
	return runUtility(CheckFormat(), args);
}
