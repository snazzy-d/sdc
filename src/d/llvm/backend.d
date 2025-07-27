module d.llvm.backend;

import d.llvm.codegen;

import d.ir.symbol;

import llvm.c.core;
import llvm.c.target;
import llvm.c.targetMachine;

final class LLVMBackend {
private:
	CodeGen pass;
	alias pass this;

	import d.llvm.config;
	LLVMConfig _config;

	LLVMTargetMachineRef targetMachine;

public:
	@property
	auto config() const {
		return _config;
	}

	import d.semantic.semantic;
	this(SemanticPass sema, LLVMConfig config, Module main) {
		this._config = config;

		import llvm.c.executionEngine;
		LLVMLinkInMCJIT();

		LLVMInitializeNativeTarget();
		LLVMInitializeNativeAsmPrinter();

		// Always use X86 intel syntax for now.
		import llvm.c.support;
		const char*[2] IntelSyntaxArgument = ["dummy", "-x86-asm-syntax=intel"];
		LLVMParseCommandLineOptions(2, IntelSyntaxArgument.ptr, null);

		version(linux) {
			enum Reloc = LLVMRelocMode.PIC;
		} else {
			enum Reloc = LLVMRelocMode.Default;
		}

		targetMachine = LLVMCreateTargetMachine(
			LLVMGetFirstTarget(),
			LLVMGetDefaultTargetTriple(),
			LLVMGetHostCPUName(),
			LLVMGetHostCPUFeatures(),
			LLVMCodeGenOptLevel.Default,
			Reloc,
			LLVMCodeModel.Default,
		);

		pass = new CodeGen(sema, main, targetMachine, config.debugBuild);
	}

	~this() {
		LLVMDisposeTargetMachine(targetMachine);
	}

	auto getEvaluator() {
		import d.llvm.evaluator;
		return new LLVMEvaluator(pass);
	;
	}

	auto getDataLayout() {
		import d.llvm.datalayout;
		return new LLVMDataLayout(pass);
	}

	void define(Function f) {
		import d.llvm.global;
		GlobalGen(pass).define(f);
	}

	private void runLLVMPasses() {
		import llvm.c.transforms.passBuilder;
		auto opts = LLVMCreatePassBuilderOptions();
		scope(exit) LLVMDisposePassBuilderOptions(opts);

		char[12] passes = "default<O?>\0";
		passes[9] = cast(char) ('0' + config.optLevel);

		LLVMRunPasses(dmodule, passes.ptr, targetMachine, opts);
	}

	private void emitModules(Module[] modules) {
		foreach (m; modules) {
			import d.llvm.global;
			GlobalGen(pass).define(m);
		}

		runLLVMPasses();
	}

	void emitObject(Module[] modules, string objFile) {
		emitModules(modules);

		import std.string;
		auto cobjFile = objFile.toStringz();

		char* errorPtr;
		if (!LLVMTargetMachineEmitToFile(
			    targetMachine, dmodule, cobjFile, LLVMCodeGenFileType.Object,
			    &errorPtr)) {
			return;
		}

		scope(exit) LLVMDisposeMessage(errorPtr);

		import core.stdc.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		throw new Exception(error);
	}

	void emitAsm(Module[] modules, string filename) {
		emitModules(modules);

		import std.string;
		auto cfilename = filename.toStringz();

		char* errorPtr;
		if (!LLVMTargetMachineEmitToFile(
			    targetMachine, dmodule, cfilename, LLVMCodeGenFileType.Assembly,
			    &errorPtr)) {
			return;
		}

		scope(exit) LLVMDisposeMessage(errorPtr);

		import core.stdc.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		throw new Exception(error);
	}

	void emitLLVMAsm(Module[] modules, string filename) {
		emitModules(modules);

		import std.string;
		auto cfilename = filename.toStringz();

		char* errorPtr;
		if (!LLVMPrintModuleToFile(dmodule, cfilename, &errorPtr)) {
			return;
		}

		scope(exit) LLVMDisposeMessage(errorPtr);

		import core.stdc.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		throw new Exception(error);
	}

	void emitLLVMBitcode(Module[] modules, string filename) {
		emitModules(modules);

		import std.string;
		auto cfilename = filename.toStringz();

		import llvm.c.bitWriter;
		if (!LLVMWriteBitcodeToFile(dmodule, filename.toStringz())) {
			return;
		}

		throw new Exception("Failed to output LLVM bitcode file.");
	}

	void link(string objFile, string executable) {
		import std.algorithm, std.array;
		auto params =
			config.linkerPaths.map!(path => " -L" ~ (cast(string) path)).join();

		import std.process;
		auto linkCommand = "gcc -o " ~ escapeShellFileName(executable) ~ " "
			~ escapeShellFileName(objFile) ~ params
			~ " -lsdrt -lphobos -lpthread -ldl";

		wait(spawnShell(linkCommand));
	}

	private auto createTestStub(Function f) {
		import d.llvm.global;
		auto globalGen = GlobalGen(pass, Mode.Eager);

		// Make sure the function we want to call is ready to go.
		auto callee = globalGen.declare(f);

		// Generate function's body. Warning: horrible hack.
		import d.llvm.local;
		auto lg = LocalGen(&globalGen);
		auto builder = lg.builder;

		auto funType = LLVMFunctionType(i64, null, 0, false);
		auto fun = LLVMAddFunction(dmodule, "__unittest", funType);

		// Personality function to handle exceptions.
		LLVMSetPersonalityFn(fun,
		                     globalGen.declare(pass.object.getPersonality()));

		auto callBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "call");
		auto thenBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "then");
		auto lpBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "lp");

		LLVMPositionBuilderAtEnd(builder, callBB);
		LLVMBuildInvoke2(builder, funType, callee, null, 0, thenBB, lpBB, "");

		LLVMPositionBuilderAtEnd(builder, thenBB);
		LLVMBuildRet(builder, LLVMConstInt(i64, 0, false));

		// Build the landing pad.
		LLVMTypeRef[2] lpTypes = [llvmPtr, i32];
		auto lpType = LLVMStructTypeInContext(llvmCtx, lpTypes.ptr,
		                                      lpTypes.length, false);

		LLVMPositionBuilderAtEnd(builder, lpBB);
		auto landingPad = LLVMBuildLandingPad(builder, lpType, null, 1, "");

		LLVMAddClause(landingPad, llvmNull);

		// We don't care about cleanup for now.
		LLVMBuildRet(builder, LLVMConstInt(i64, 1, false));

		return fun;
	}

	auto runUnittests(Module[] modules) {
		// We do all the code generation as a first pass so we
		// avoid JITing multiple variations of the same code.
		static struct Test {
			Function unit;
			LLVMValueRef stub;

			this(LLVMBackend b, Function t) {
				unit = t;
				stub = b.createTestStub(t);
			}
		}

		Test[] tests;
		foreach (m; modules) {
			foreach (t; m.tests) {
				import source.name;
				tests ~= Test(this, t);
			}
		}

		import d.llvm.global;
		GlobalGen(pass).checkModule();

		runLLVMPasses();

		// Now that we generated the IR, we run the unittests.
		import d.llvm.engine;
		auto ee = createExecutionEngine(dmodule);
		scope(exit) destroyExecutionEngine(ee, dmodule);

		struct Result {
			import std.bitmanip;
			mixin(taggedClassRef!(
				// sdfmt off
				Function, "test",
				bool, "pass", 1,
				// sdfmt on
			));

			this(Function test, bool pass) {
				this.test = test;
				this.pass = pass;
			}
		}

		Result[] results;

		foreach (t; tests) {
			import llvm.c.executionEngine;
			auto result = LLVMRunFunction(ee, t.stub, 0, null);
			scope(exit) LLVMDisposeGenericValue(result);

			// Check the return value and report.
			// TODO: We need to make a specific report of the failure
			// if indeed there is failure.
			bool pass = !LLVMGenericValueToInt(result, false);
			results ~= Result(t.unit, pass);
		}

		return results;
	}
}
