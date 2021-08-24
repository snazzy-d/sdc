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
	
	import sdc.util.json, d.config;
	this(string name, JSON fileConfig, Config config) {
		import std.algorithm, std.array, std.conv, std.path, std.range;
		config.includePaths = fileConfig["includePath"]
			.array
			.map!(p => cast(string) p)
			.chain(config.includePaths)
			.map!(p => expandTilde(p)
				.asAbsolutePath
				.asNormalizedPath
				.to!string())
			.array();
		
		auto linkerPaths = fileConfig["libPath"]
			.array
			.map!(path => cast(string) path)
			.array();
		
		config.linkerPaths = linkerPaths ~ config.linkerPaths;
		
		context = new Context();
		
		LLVMBackend evBackend;
		
		import d.semantic.evaluator;
		Evaluator evb(SemanticPass pass) {
			if (evBackend is null) {
				evBackend = new LLVMBackend(pass, name);
			}
			
			return evBackend.getEvaluator();
		}
		
		import d.semantic.datalayout, d.object;
		DataLayout dlb(ObjectReference) {
			assert(evBackend !is null);
			return evBackend.getDataLayout();
		}
		
		semantic = new SemanticPass(context, config, &evb, &dlb);
		backend = new LLVMBackend(semantic, name);
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
