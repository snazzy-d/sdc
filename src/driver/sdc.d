module driver.sdc;

import source.context;

int main(string[] args) {
	import util.main;
	return runMain!run(args);
}

int run(Context context, string[] args) {
	import sdc.config;
	Config conf;

	import config.build;
	conf.buildGlobalConfig("sdconfig", context);

	string[] includePaths, linkerPaths;
	bool dontLink, debugBuild, generateMain;
	string outputFile, deps, makedeps;
	bool outputLLVM, outputAsm;

	import std.getopt;
	auto help_info = getopt(
		// sdfmt off
		args, std.getopt.config.caseSensitive,
		"I",         "Include path",        &includePaths,
		"L",         "Library path",        &linkerPaths,
		"O",         "Optimization level",  &conf.optLevel,
		"c",         "Stop before linking", &dontLink,
		"o",         "Output file",         &outputFile,
		"g",         "Generate source-level debug information", &debugBuild,
		"S",         "Stop before assembling and output assembly file", &outputAsm,
		"emit-llvm", "Output LLVM bitcode (-c) or LLVM assembly (-S)",  &outputLLVM,
		"deps",      "Write a dependency file to FILE", &deps,
		"makedeps",  "Write a makefile dependency file to FILE, with phony targets", &makedeps,
		"main",      "Generate the main function", &generateMain,
		// sdfmt on
	);

	if (help_info.helpWanted || args.length == 1) {
		import std.stdio;
		writeln("The Snazzy D Compiler");
		writeln("Usage: sdc [options] file.d");
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

	if (includePaths == []) {
		includePaths = ["."];
	}

	conf.includePaths = includePaths ~ conf.includePaths;
	conf.linkerPaths = linkerPaths ~ conf.linkerPaths;

	auto files = args[1 .. $];

	if (outputAsm) {
		dontLink = true;
	}

	auto executable = "a.out";
	auto defaultExtension = ".o";
	if (outputAsm) {
		defaultExtension = outputLLVM ? ".ll" : ".s";
	} else if (dontLink) {
		defaultExtension = outputLLVM ? ".bc" : ".o";
	}

	import std.path;
	auto objFile = files[0].setExtension(defaultExtension);
	if (outputFile.length) {
		if (dontLink || outputAsm) {
			objFile = outputFile;
		} else {
			executable = outputFile;
		}
	}

	// If we are generating an executable, we want a main function.
	generateMain = generateMain || !dontLink;

	// The target to use for build systems.
	auto target = (dontLink || outputAsm) ? objFile : executable;

	// Cannot call the variable "sdc" or DMD complains about name clash
	// with the sdc package from the import.
	import sdc.sdc;
	auto c = new SDC(context, files[0], conf, files, debugBuild);

	if (generateMain) {
		c.buildMain();
	}

	if (outputAsm) {
		if (outputLLVM) {
			c.outputLLVMAsm(objFile);
		} else {
			c.outputAsm(objFile);
		}
	} else if (dontLink) {
		if (outputLLVM) {
			c.outputLLVMBitcode(objFile);
		} else {
			c.outputObj(objFile);
		}
	} else {
		c.outputObj(objFile);
		c.linkExecutable(objFile, executable);
	}

	if (deps.length > 0) {
		c.emitDepfile(deps, target, false);
	}

	if (makedeps.length > 0) {
		c.emitDepfile(makedeps, target, true);
	}

	return 0;
}
