/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.main;

import d.ast.dmodule;

import d.exception;

import sdc.conf;
import sdc.sdc;
import sdc.terminal;

import std.array;
import std.getopt;

int main(string[] args) {
	version(DigitalMars) {
		version(linux) {
			import etc.linux.memoryerror;
			// druntime not containe the necessary symbol.
			// registerMemoryErrorHandler();
		}
	}
	
	auto conf = buildConf();
	
	string[] includePath;
	uint optLevel;
	bool dontLink;
	string outputFile;

	auto help_info = getopt(
		args, std.getopt.config.caseSensitive,
		"I", "Include path",        &includePath,
		"O", "Optimization level",  &optLevel,
		"c", "Stop before linking", &dontLink,
		"o", "Output file",         &outputFile
	);

	if (help_info.helpWanted || args.length == 1) {
		import std.stdio;
		writeln("The Stupid D Compiler");
		writeln("Usage: sdc <options> file.d");
		writeln("Options:");
		
		foreach (option; help_info.options) {
			writefln(
				"%5s : %s",
				// bug : optShort is empty if there is no long version
				option.optShort.length ? option.optShort : option.optLong[1 .. $],
				option.help
			);
		}
		return 0;
	}

	foreach(path; includePath) {
		conf["includePath"] ~= path;
	}
	
	auto files = args[1 .. $];
	
	// Generate filenames for output artifacts (if not specified on commandline)
	import std.path : baseName, stripExtension;
	auto stripped_filename = baseName(stripExtension(files[0]));
	auto executable = stripped_filename;
	version(Windows) executable ~= ".exe";
	auto objFile = stripped_filename ~ ".o";
	if (outputFile.length) {
		if (dontLink) {
			objFile = outputFile;
		} else {
			executable = outputFile;
		}
	}
	
	auto sdc = new SDC(files[0], conf, optLevel);
	try {
		foreach(file; files) {
			sdc.compile(file);
		}
		
		if (dontLink) {
			sdc.codeGen(objFile);
		} else {
			sdc.buildMain();
			sdc.codeGen(objFile, executable);
		}
		
		return 0;
	} catch(CompileException e) {
		outputCaretDiagnostics(e.getFullLocation(sdc.context), e.msg);
		
		// Rethrow in debug, so we have the stack trace.
		debug {
			throw e;
		} else {
			return 1;
		}
	}
}

