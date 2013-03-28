/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.main;

import d.ast.dmodule;

import d.exception;

import sdc.sdc;
import sdc.terminal;

import etc.linux.memoryerror;

import std.array;
import std.getopt;

int main(string[] args) {
	version(linux) {
		registerMemoryErrorHandler();
	}
	
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
		"help|h", delegate() {
			import std.stdio;
			writeln("HELP !");
		}
	);
	
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
	
	auto sdc = new SDC(files[0], includePath, optLevel);
	try {
		Module[] mods;
		foreach(file; files) {
			mods ~= sdc.compile(file);
		}
	
		sdc.buildMain(mods);
	
		if(dontLink) {
			sdc.codeGen(objFile);
		} else {
			sdc.codeGen(objFile, executable);
		}
	
		return 0;
	} catch(CompileException e) {
		outputCaretDiagnostics(e.location, e.msg);
		
		throw e;
	}
}

