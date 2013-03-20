/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

// TODO: move that into druntime.
// Ensure that null pointers are detected.
import etc.linux.memoryerror;

import d.ast.dmodule;

import d.llvm.evaluator;
import d.llvm.backend;

import d.parser.base;

import d.semantic.semantic;

import d.exception;
import d.location;

import std.array;
import std.file;

final class SDC {
	LLVMBackend backend;
	LLVMEvaluator evaluator;
	SemanticPass semantic;
	
	string[] includePath;
	
	Module[string[]] modules;
	
	this(string name, string[] includePath, uint optLevel) {
		backend	= new LLVMBackend(name, optLevel);
		evaluator = new LLVMEvaluator(backend.pass);
		semantic = new SemanticPass(evaluator);
		
		this.includePath = ["../libs", "."] ~ includePath;
		
		compile(["object"]);
	}
	
	string[] compile(string filename) {
		auto packages = filename[0 .. $ - 2].split("/").array();
		compile(packages, new FileSource(filename));
		
		return packages;
	}
	
	void compile(string[] packages) {
		compile(packages, getFileSource(packages));
	}
	
	void compile(string[] packages, FileSource source) {
		auto trange = lex!((line, index, length) => Location(source, line, index, length))(source.content);
		
		auto ast = trange.parse(packages[$ - 1], packages[0 .. $-1]);
		semantic.schedule(ast);
		modules[packages.idup] = ast;
	}
	
	void buildMain(string[] packages) {
		semantic.terminate();
		
		import d.semantic.main;
		modules[packages.idup] = buildMain(modules[packages]);
	}
	
	void codeGen(string objFile) {
		semantic.terminate();
		
		foreach(mod; modules.values) {
			backend.codeGen(mod);
		}
		
		backend.emitObject(objFile);
	}
	
	void codeGen(string objFile, string executable) {
		codeGen(objFile);
		
		backend.link(objFile, executable);
	}
	
	FileSource getFileSource(string[] packages) {
		auto filename = "/" ~ packages.join("/") ~ ".d";
		foreach(path; includePath) {
			auto fullpath = path ~ filename;
			if(exists(fullpath)) {
				return new FileSource(fullpath);
			}
		}
		
		assert(0, "filenotfoundmalheur !");
	}
}

