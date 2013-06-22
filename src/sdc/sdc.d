/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

import d.ir.symbol;

import d.llvm.backend;

import d.semantic.semantic;

import d.location;

import std.array;
import std.file;

final class SDC {
	SemanticPass semantic;
	LLVMBackend backend;
	
	string[] includePath;
	
	Module[] modules;
	
	this(string name, string[] includePath, uint optLevel) {
		this.includePath = ["../libs", "."] ~ includePath;
		
		backend	= new LLVMBackend(name, optLevel);
		semantic = new SemanticPass(backend, backend.evaluator, &getFileSource);
	}
	
	void compile(string filename) {
		auto packages = filename[0 .. $ - 2].split("/").array();
		modules ~= semantic.add(new FileSource(filename), packages);
	}
	
	void compile(string[] packages) {
		modules ~= semantic.add(getFileSource(packages), packages);
	}
	
	void buildMain() {
		semantic.terminate();
		
		semantic.buildMain(modules);
	}
	
	void codeGen(string objFile) {
		semantic.terminate();
		
		backend.emitObject(modules, objFile);
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

