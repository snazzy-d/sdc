module sdc.sdc;

final class SDC {
	import source.context;
	Context context;

	import d.semantic.semantic;
	SemanticPass semantic;

	import d.llvm.backend;
	LLVMBackend backend;

	import d.ir.symbol;
	Module[] modules;

	import sdc.config;
	this(Context context, string name, Config config, string[] preload = [],
	     bool debugBuild = false) {
		this.context = context;

		import std.algorithm, std.array, std.conv, std.path;
		auto includePaths = config
			.includePaths
			.map!(
				p => expandTilde(p).asAbsolutePath.asNormalizedPath.to!string())
			.array();

		LLVMBackend evBackend;

		import d.llvm.config;
		auto getEvaluatorBackend(SemanticPass pass) {
			if (evBackend is null) {
				evBackend = new LLVMBackend(pass, LLVMConfig(config, false),
				                            modules[0]);
			}

			return evBackend;
		}

		import d.semantic.evaluator;
		Evaluator getEvaluator(SemanticPass pass) {
			return getEvaluatorBackend(pass).getEvaluator();
		}

		import d.semantic.datalayout, d.object;
		DataLayout getDataLayout(SemanticPass pass) {
			return getEvaluatorBackend(pass).getDataLayout();
		}

		semantic = new SemanticPass(
			context, includePaths, preload, modules, config.enableUnittest,
			&getEvaluator, &getDataLayout);
		backend = new LLVMBackend(semantic, LLVMConfig(config, debugBuild),
		                          modules[0]);
	}

	void compile(string filename) {
		modules ~= semantic.add(filename);
	}

	void buildMain() {
		semantic.terminate();
		backend.define(semantic.buildMain(modules[0]));
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

	auto runUnittests() {
		semantic.terminate();
		return backend.runUnittests(modules);
	}
}
