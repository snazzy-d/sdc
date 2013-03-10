/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

// TODO: move that into druntime.
// Ensure that null pointers are detected.
import etc.linux.memoryerror;

import d.parser.base;

import d.exception;

import std.stdio : writeln, stderr, stdout;
import std.file : exists;

import std.array;

int main(string[] args) {
	if (args.length == 1) {
		stderr.writeln("usage: sdc file");
		return 1;
	}
	
	try {
		foreach (file; args[1..$]) {
			compile(file);
		}
	} catch(CompileException e) {
		import sdc.terminal;
		outputCaretDiagnostics(e.location, e.msg);
		
		debug {
			throw e;
		} else {
			return 1;
		}
	}
	
	return 0;
}

void compile(string filename) {
	import std.stdio;
	auto fileSource = new FileSource(filename);
	auto trange = lex!((line, index, length) => Location(fileSource, line, index, length))(fileSource.content);
	
	auto objectSource = new FileSource("../libs/object.d");
	FileSource[16] objectSources;
	objectSources[] = objectSource;
	auto object = lex!((line, index, length) => Location(objectSource, line, index, length))(objectSource.content);
	
	auto packages = filename[0 .. $-2].split("/");
	auto ast = [object.parse("object", []), trange.parse(packages.back, packages[0 .. $-1])];
	
	// Test the new scheduler system.
	import d.semantic.semantic;
	
	import d.llvm.evaluator;
	import d.llvm.backend;
	auto backend	= new LLVMBackend(ast.back.location.source.filename);
	auto evaluator	= new LLVMEvaluator(backend.pass);
	
	auto semantic = new SemanticPass(evaluator);
	ast = semantic.process(ast);
	
	import d.semantic.main;
	ast.back = buildMain(ast.back);
	
	//*
	backend.codeGen([ast.back]);
	//*/
}

