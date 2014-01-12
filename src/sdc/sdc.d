/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

import d.ir.symbol;

import d.llvm.backend;

import d.semantic.semantic;

import d.context;
import d.location;

import std.algorithm;
import std.array;
import std.file;

final class SDC {
	Context context;
	
	SemanticPass semantic;
	LLVMBackend backend;
	
	string[] includePath;
	
	Module[] modules;
	
	this(string name, string[] includePath, uint optLevel) {
		this.includePath = ["../libs", "."] ~ includePath;
		
		context = new Context();
		
		backend	= new LLVMBackend(context, name, optLevel);
		semantic = new SemanticPass(context, backend.evaluator, &getFileSource);
	}
	
	void compile(string filename) {
		auto packages = filename[0 .. $ - 2].split("/").map!(p => context.getName(p)).array();
		modules ~= semantic.add(new FileSource(filename), packages);
	}
	
	void compile(Name[] packages) {
		modules ~= semantic.add(getFileSource(packages), packages);
	}
	
	void buildMain() {
		semantic.terminate();
		
		backend.visit(semantic.buildMain(modules));
	}
	
	void codeGen(string objFile) {
		semantic.terminate();
		
		backend.emitObject(modules, objFile);
	}
	
	void codeGen(string objFile, string executable) {
		codeGen(objFile);
		
		backend.link(objFile, executable);
	}
	
	FileSource getFileSource(Name[] packages) {
		auto filename = "/" ~ packages.map!(p => p.toString(context)).join("/") ~ ".d";
		foreach(path; includePath) {
			auto fullpath = path ~ filename;
			if(exists(fullpath)) {
				return new FileSource(fullpath);
			}
		}
		
		assert(0, "filenotfoundmalheur !");
	}
}

