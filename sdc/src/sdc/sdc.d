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
		import std.algorithm, std.array, std.conv, std.path;
		auto includePaths = conf["includePath"]
			.array
			.map!(p => expandTilde(cast(string) p)
				.asAbsolutePath
				.asNormalizedPath
				.to!string())
			.array();
		
		auto linkerParams = conf["libPath"]
			.array
			.map!(path => " -L" ~ (cast(string) path))
			.join();
		
		context = new Context();
		
		LLVMBackend evBackend;
		
		import d.object, d.semantic.scheduler, d.semantic.evaluator;
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
		modules ~= semantic.add(filename);
	}
	
	void buildMain() {
		semantic.terminate();
		backend.visit(semantic.buildMain(modules[0]));
	}
	
	void outputLLVMAsm(string filename) {
		semantic.terminate();
		backend.emitLLVMAsm(modules, filename);
	}
	
	void outputLLVMBitcode(string filename) {
		semantic.terminate();
		backend.emitLLVMBitcode(modules, filename);
	}
	
	void outputAsm(string filename) {
		semantic.terminate();
		backend.emitAsm(modules, filename);
	}
	
	void outputObj(string objFile) {
		semantic.terminate();
		backend.emitObject(modules, objFile);
	}
	
	void linkExecutable(string objFile, string executable) {
		backend.link(objFile, executable);
	}
}
