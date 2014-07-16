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
	getopt(
		args, std.getopt.config.caseSensitive,
		"I", &includePath,
		"O", &optLevel,
		"c", &dontLink,
		"o", &outputFile,
		"help|h",&printHelp
	);
	
	foreach(path; includePath) {
		conf["includePath"] ~= path;
	}
	
	auto files = args[1 .. $];
	
	auto executable = "a.out";
	auto objFile = files[0][0 .. $-2] ~ ".o";
	if(outputFile.length) {
		if(dontLink) {
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
		
		if(dontLink) {
			sdc.codeGen(objFile);
		} else {
			sdc.buildMain();
			sdc.codeGen(objFile, executable);
		}
		
		return 0;
	} catch(CompileException e) {
		outputCaretDiagnostics(e.location, e.msg);
		
		// Rethrow in debug, so we have the stack trace.
		debug {
			throw e;
		} else {
			return 1;
		}
	}
}

void printHelp() {
	import std.stdio;
	writeln("usage: sdc [-IOco] inputfile");
	writeln("-o outfile | sets the outputfile to outfile");
	writeln("-I includepaths ... | ");
	writeln("-c | don't link");
}
