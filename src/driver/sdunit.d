module driver.dsunit;

import source.context;

immutable string[2] ResultStr = ["FAIL", "PASS"];

int main(string[] args) {
	import util.main;
	return runMain!run(args);
}

int run(Context context, string[] args) {
	import sdc.config;
	Config conf;

	import config.build;
	conf.buildGlobalConfig("sdconfig", context);

	conf.enableUnittest = true;

	string[] includePaths, linkerPaths;

	import std.getopt;
	auto help_info = getopt(
		// sdfmt off
		args, std.getopt.config.caseSensitive,
		"I",         "Include path",        &includePaths,
		"L",         "Library path",        &linkerPaths,
		"O",         "Optimization level",  &conf.optLevel,
		// sdfmt on
	);

	if (help_info.helpWanted || args.length == 1) {
		import std.stdio;
		writeln("The Snazzy D Compiler - Unit test JIT");
		writeln("Usage: sdunit [options] file.d");
		writeln("Options:");

		foreach (option; help_info.options) {
			writefln(
				"  %-16s %s",
				// bug : optShort is empty if there is no long version
				option.optShort.length
					? option.optShort
					: (option.optLong.length == 3)
						? option.optLong[1 .. $]
						: option.optLong,
				option.help
			);
		}

		return 0;
	}

	conf.includePaths = includePaths ~ conf.includePaths;
	conf.linkerPaths = linkerPaths ~ conf.linkerPaths;

	auto files = args[1 .. $];

	// Cannot call the variable "sdc" or DMD complains about name clash
	// with the sdc package from the import.
	import sdc.sdc;
	auto c = new SDC(context, files[0], conf, files);

	import d.ir.symbol;
	Module m = null;

	bool returnCode = 0;
	auto results = c.runUnittests();
	if (results.length == 0) {
		import std.stdio;
		writeln("No test to run");
		return 0;
	}

	import std.stdio;
	write("Test results:");

	foreach (r; results) {
		if (!r.pass) {
			returnCode = 1;
		}

		auto testModule = r.test.getModule();
		if (m != testModule) {
			m = testModule;

			import source.context;
			static void printModule(P)(Context c, P p) {
				if (p.parent is null) {
					import std.stdio;
					write("\nModule ", p.toString(c));
					return;
				}

				printModule(c, p.parent);

				import std.stdio;
				write(".", p.toString(c));

				static if (is(P : Module)) {
					writeln(":");
				}
			}

			printModule(c.context, m);
		}

		auto name = r.test.name.toString(c.context);

		import std.stdio;
		writefln("\t%-24s %s", name, ResultStr[r.pass]);
	}

	return returnCode;
}
