/**
 * Entry point for the new multi-pass experiment.
 */
module sdc.sdc;

import d.ir.symbol;

import d.llvm.backend;

import d.semantic.semantic;

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
		
		LLVMBackend evBackend;
		
		import d.object;
		import d.semantic.scheduler, d.semantic.evaluator;
		Evaluator evb(Scheduler scheduler, ObjectReference obj) {
			if (evBackend is null) {
				evBackend = new LLVMBackend(
					context,
					scheduler,
					obj,
					name,
					optLevel,
					linkerParams,
				);
			}
			
			return evBackend.getEvaluator();
		}
		
		import d.semantic.datalayout;
		DataLayout dlb(ObjectReference) {
			assert(evBackend !is null);
			return evBackend.getDataLayout();
		}
		
		SemanticPass.DataLayoutBuilder stuff = &dlb;
		
		semantic = new SemanticPass(context, &evb, &dlb, includePaths);
		backend = new LLVMBackend(
			context,
			semantic.scheduler,
			semantic.object,
			name,
			optLevel,
			linkerParams,
		);
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
