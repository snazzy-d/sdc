module d.llvm.backend;

import d.llvm.codegen;
import d.llvm.evaluator;
import d.llvm.datalayout;

import d.ir.symbol;

import llvm.c.core;
import llvm.c.target;
import llvm.c.targetMachine;

final class LLVMBackend {
private:
	CodeGen pass;

	uint optLevel;
	string[] linkerPaths;

	LLVMEvaluator evaluator;
	LLVMDataLayout dataLayout;

	LLVMTargetMachineRef targetMachine;

public:
	import d.semantic.semantic;
	this(SemanticPass sema, string name, uint optLevel, string[] linkerPaths) {
		this.optLevel = optLevel;
		this.linkerPaths = linkerPaths;

		LLVMInitializeX86TargetInfo();
		LLVMInitializeX86Target();
		LLVMInitializeX86TargetMC();

		import llvm.c.executionEngine;
		LLVMLinkInMCJIT();
		LLVMInitializeX86AsmPrinter();

		version(OSX) {
			auto triple = "x86_64-apple-darwin9".ptr;
		} else version(FreeBSD) {
			auto triple = "x86_64-unknown-freebsd".ptr;
		} else {
			auto triple = "x86_64-pc-linux-gnu".ptr;
		}

		version(linux) {
			enum Reloc = LLVMRelocMode.PIC;
		} else {
			enum Reloc = LLVMRelocMode.Default;
		}

		targetMachine = LLVMCreateTargetMachine(
			LLVMGetFirstTarget(), triple, "x86-64".ptr, "".ptr,
			LLVMCodeGenOptLevel.Default, Reloc, LLVMCodeModel.Default);

		auto td = LLVMCreateTargetDataLayout(targetMachine);
		scope(exit) LLVMDisposeTargetData(td);

		pass = new CodeGen(sema, name, this, td);
		dataLayout = new LLVMDataLayout(pass, pass.targetData);
	}

	~this() {
		LLVMDisposeTargetMachine(targetMachine);
	}

	auto getPass() {
		return pass;
	}

	auto getEvaluator() {
		if (evaluator is null) {
			evaluator = new LLVMEvaluator(pass);
		}

		return evaluator;
	}

	auto getDataLayout() {
		return dataLayout;
	}

	void visit(Module mod) {
		pass.visit(mod);
	}

	void visit(Function f) {
		import d.llvm.global;
		GlobalGen(pass).define(f);
	}

	private void runLLVMPasses(Module[] modules) {
		foreach (m; modules) {
			pass.visit(m);
		}

		import llvm.c.transforms.passManagerBuilder;
		auto pmb = LLVMPassManagerBuilderCreate();
		scope(exit) LLVMPassManagerBuilderDispose(pmb);

		uint optLevel = optLevel;
		if (optLevel == 0) {
			LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 0);
			LLVMPassManagerBuilderSetOptLevel(pmb, 0);
		} else {
			LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 100);
			LLVMPassManagerBuilderSetOptLevel(pmb, optLevel);
		}

		auto pm = LLVMCreatePassManager();
		scope(exit) LLVMDisposePassManager(pm);

		LLVMPassManagerBuilderPopulateModulePassManager(pmb, pm);
		LLVMRunPassManager(pm, pass.dmodule);
	}

	void emitObject(Module[] modules, string objFile) {
		runLLVMPasses(modules);

		import std.string;
		char* errorPtr;
		auto emitError = LLVMTargetMachineEmitToFile(
			targetMachine, pass.dmodule, objFile.toStringz(),
			LLVMCodeGenFileType.Object, &errorPtr);

		if (emitError) {
			scope(exit) LLVMDisposeMessage(errorPtr);

			import core.stdc.string, std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);

			assert(0, "Fail to emit object file ! Exiting...");
		}
	}

	void emitAsm(Module[] modules, string filename) {
		runLLVMPasses(modules);

		import std.string;
		char* errorPtr;
		auto printError = LLVMTargetMachineEmitToFile(
			targetMachine, pass.dmodule, filename.toStringz(),
			LLVMCodeGenFileType.Assembly, &errorPtr);

		if (printError) {
			scope(exit) LLVMDisposeMessage(errorPtr);

			import core.stdc.string, std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);

			assert(0, "Failed to output assembly file! Exiting...");
		}
	}

	void emitLLVMAsm(Module[] modules, string filename) {
		runLLVMPasses(modules);

		import std.string;
		char* errorPtr;
		auto printError =
			LLVMPrintModuleToFile(pass.dmodule, filename.toStringz(),
			                      &errorPtr);

		if (printError) {
			scope(exit) LLVMDisposeMessage(errorPtr);

			import core.stdc.string, std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);

			assert(0, "Failed to output LLVM assembly file! Exiting...");
		}
	}

	void emitLLVMBitcode(Module[] modules, string filename) {
		runLLVMPasses(modules);

		import llvm.c.bitWriter;
		import std.string;
		auto error = LLVMWriteBitcodeToFile(pass.dmodule, filename.toStringz());
		if (error) {
			assert(0, "Failed to output LLVM bitcode file! Exiting...");
		}
	}

	void link(string objFile, string executable) {
		import std.algorithm, std.array;
		auto params =
			linkerPaths.map!(path => " -L" ~ (cast(string) path)).join();

		import std.process;
		auto linkCommand = "gcc -o " ~ escapeShellFileName(executable) ~ " "
			~ escapeShellFileName(objFile) ~ params
			~ " -lsdrt -lphobos -lpthread";

		wait(spawnShell(linkCommand));
	}

	auto runUnittests(Module[] modules) {
		// In a first step, we do all the codegen.
		// We need to do it in a first step so that we can reuse
		// one instance of MCJIT.
		auto e = getEvaluator();

		struct Test {
			Function unit;
			LLVMValueRef stub;

			this(LLVMEvaluator e, Function t) {
				unit = t;
				stub = e.createTestStub(t);
			}
		}

		Test[] tests;
		foreach (m; modules) {
			foreach (t; m.tests) {
				import source.name;
				tests ~= Test(e, t);
			}
		}

		// Now that we generated the IR, we run the unittests.
		import d.llvm.evaluator;
		auto ee = createExecutionEngine(pass.dmodule);
		scope(exit) destroyExecutionEngine(ee, pass.dmodule);

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
