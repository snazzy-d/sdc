/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

import d.ir.symbol;

import d.llvm.backend;

import d.semantic.semantic;

import d.location;

import util.json;

final class SDC {
	import d.base.context;
	Context context;
	
	SemanticPass semantic;
	LLVMBackend backend;
	
	string[] includePath;
	
	Module[] modules;
	
	this(string name, JSON conf, uint optLevel) {
		import std.algorithm, std.array;
		includePath = conf["includePath"].array.map!(path => cast(string) path).array();
		
		context = new Context();
		
		backend	= new LLVMBackend(context, name, optLevel, conf["libPath"].array.map!(path => " -L" ~ (cast(string) path)).join());
		semantic = new SemanticPass(context, backend.getEvaluator(), backend.getDataLayout(), &getFileSource);
		
		// Review thet way this whole thing is built.
		backend.getPass().object = semantic.object;
	}
	
	void compile(string filename) {
		import std.algorithm, std.array;
		auto packages = filename[0 .. $ - 2].split("/").map!(p => context.getName(p)).array();
		modules ~= semantic.add(new FileSource(filename), packages);
	}
	
	import d.base.name;
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
		import std.algorithm, std.array;
		auto filename = "/" ~ packages.map!(p => p.toString(context)).join("/") ~ ".d";
		foreach(path; includePath) {
			auto fullpath = path ~ filename;

			import std.file;
			if (exists(fullpath)) {
				return new FileSource(fullpath);
			}
		}
		
		assert(0, "filenotfoundmalheur ! " ~ filename);
	}
}

