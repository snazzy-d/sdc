/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.main;

import d.exception;

import sdc.conf;
import sdc.sdc;

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
	bool dontLink, generateMain;
	string outputFile;
	bool outputLLVM, outputAsm;
	
	import std.getopt;
	auto help_info = getopt(
		args, std.getopt.config.caseSensitive,
		"I",         "Include path",        &includePath,
		"O",         "Optimization level",  &optLevel,
		"c",         "Stop before linking", &dontLink,
		"o",         "Output file",         &outputFile,
		"S",         "Stop before assembling and output assembly file", &outputAsm,
		"emit-llvm", "Output LLVM bitcode (-c) or LLVM assembly (-S)",  &outputLLVM,
		"main",      "Generate the main function", &generateMain,
	);
	
	if (help_info.helpWanted || args.length == 1) {
		import std.stdio;
		writeln("The Stupid D Compiler");
		writeln("Usage: sdc <options> file.d");
		writeln("Options:");
		
		foreach (option; help_info.options) {
			writefln(
				"  %-12s %s",
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
	
	foreach (path; includePath) {
		conf["includePath"] ~= path;
	}
	
	auto files = args[1 .. $];
	
	if (outputAsm) dontLink = true;
	
	auto executable = "a.out";
	auto defaultExtension = ".o";
	if (outputAsm) {
		defaultExtension = outputLLVM ? ".ll" : ".s";
	} else if (dontLink) {
		defaultExtension = outputLLVM ? ".bc" : ".o";
	}
	
	auto objFile = files[0][0 .. $-2] ~ defaultExtension;
	if (outputFile.length) {
		if (dontLink || outputAsm) {
			objFile = outputFile;
		} else {
			executable = outputFile;
		}
	}
	
	// If we are generating an executable, we want a main function.
	generateMain = generateMain || !dontLink;
	
	auto sdc = new SDC(files[0], conf, optLevel);
	try {
		foreach (file; files) {
			sdc.compile(file);
		}
		
		if (generateMain) {
			sdc.buildMain();
		}
		
		if (outputAsm) {
			if (outputLLVM) {
				sdc.outputLLVMAsm(objFile);
			} else {
				sdc.outputAsm(objFile);
			}
		} else if (dontLink) {
			if (outputLLVM) {
				sdc.outputLLVMBitcode(objFile);
			} else {
				sdc.outputObj(objFile);
			}
		} else {
			sdc.outputObj(objFile);
			sdc.linkExecutable(objFile, executable);
		}
		
		return 0;
	} catch(CompileException e) {
		import util.terminal;
		outputCaretDiagnostics(e.getFullLocation(sdc.context), e.msg);
		
		// Rethrow in debug, so we have the stack trace.
		debug {
			throw e;
		} else {
			return 1;
		}
	}
}
