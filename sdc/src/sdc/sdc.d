/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

import d.ir.symbol;

import d.llvm.backend;

import d.semantic.semantic;

import d.context.source;

import util.json;

final class SDC {
	import d.context.context;
	Context context;
	
	SemanticPass semantic;
	LLVMBackend backend;
	
	Module[] modules;
	
	this(string name, JSON conf, uint optLevel) {
		import std.algorithm, std.array;
		auto includePaths = conf["includePath"].array.map!(path => cast(string) path).array();
		auto linkerParams = conf["libPath"].array.map!(path => " -L" ~ (cast(string) path)).join();
		
		context = new Context();
		
		backend	= new LLVMBackend(context, name, optLevel, linkerParams);
		semantic = new SemanticPass(context, backend.getEvaluator(), backend.getDataLayout(), includePaths);
		
		// Review thet way this whole thing is built.
		backend.getPass().object = semantic.object;
	}
	
	void compile(string filename) {
		import std.algorithm, std.array;
		auto packages = filename[0 .. $ - 2].split("/").map!(p => context.getName(p)).array();
		modules ~= semantic.add(filename, packages);
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
}
