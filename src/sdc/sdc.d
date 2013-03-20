/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

// TODO: move that into druntime.
// Ensure that null pointers are detected.
import etc.linux.memoryerror;

import d.ast.dmodule;

import d.llvm.backend;

import d.semantic.semantic;

import d.location;

import std.array;
import std.file;

final class SDC {
	SemanticPass semantic;
	LLVMBackend backend;
	
	string[] includePath;
	
	this(string name, string[] includePath, uint optLevel) {
		this.includePath = ["../libs", "."] ~ includePath;
		
		backend	= new LLVMBackend(name, optLevel);
		semantic = new SemanticPass(backend, backend.evaluator, &getFileSource);
	}
	
	Module compile(string filename) {
		auto packages = filename[0 .. $ - 2].split("/").array();
		return semantic.add(new FileSource(filename), packages);
	}
	
	Module compile(string[] packages) {
		return semantic.add(getFileSource(packages), packages);
	}
	
	void buildMain(Module[] mods) {
		semantic.terminate();
		
		semantic.buildMain(mods);
	}
	
	void codeGen(string objFile) {
		semantic.terminate();
		
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

