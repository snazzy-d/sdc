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
	this(Context context, string name, Config config, string[] preload = []) {
		this.context = context;

		import std.algorithm, std.array, std.conv, std.path;
		auto includePaths = config
			.includePaths
			.map!(
				p => expandTilde(p).asAbsolutePath.asNormalizedPath.to!string())
			.array();

		LLVMBackend evBackend;

		import d.semantic.evaluator;
		Evaluator evb(SemanticPass pass) {
			if (evBackend is null) {
				evBackend = new LLVMBackend(pass, name, config.optLevel,
				                            config.linkerPaths);
			}

			return evBackend.getEvaluator();
		}

		import d.semantic.datalayout, d.object;
		DataLayout dlb(ObjectReference) {
			assert(evBackend !is null);
			return evBackend.getDataLayout();
		}

		semantic = new SemanticPass(context, includePaths, preload, modules,
		                            config.enableUnittest, &evb, &dlb);
		backend = new LLVMBackend(semantic, name, config.optLevel,
		                          config.linkerPaths);
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

	auto runUnittests() {
		semantic.terminate();
		return backend.runUnittests(modules);
	}
}
