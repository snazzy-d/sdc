#!/usr/bin/env -S sh -c 'rdmd -I`dirname "$0"` "$0" "$@"'
/**
 * Copyright 2010-2011 Bernard Helyer
 * Copyright 2011 Jakob Ovrum
 */
module checkformat;

import util;

immutable SDFMT = "bin/sdfmt";

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
			stderr.writefln("%s: sdfmt expected to format, did not (%d).", name,
			                result.status);
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
	alias ExtraArgs =
		AliasSeq!("formatter", "The formatter executable to use.", string);

	string formatter;

	void processArgs(string formatter) {
		this.formatter = getAbsolutePath(formatter);
	}

	auto getTasks(string[] args) {
		if (formatter == "") {
			formatter = getAbsolutePath(SDFMT);
		}

		import std.algorithm, std.array, std.file;
		return [
			"test/compilable", "test/format", "test/invalid", "test/runner",
			"test/unit", "test/valid", "sdlib/d", "src",
		].map!(d => dirEntries(d, "*.d", SpanMode.breadth)).join()
		 .filter!(f => f.isFile()).map!(t => Task(t, formatter));
	}
}

int main(string[] args) {
	return runUtility(CheckFormat(), args);
}
