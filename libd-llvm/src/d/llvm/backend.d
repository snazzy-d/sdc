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
	
	LLVMEvaluator evaluator;
	LLVMDataLayout dataLayout;
	
	LLVMTargetMachineRef targetMachine;
	
	uint optLevel;
	string linkerParams;
	
public:
	import d.context.context, d.semantic.scheduler, d.object;
	this(
		Context context,
		Scheduler scheduler,
		ObjectReference obj,
		string name,
		uint optLevel,
		string linkerParams,
	) {
		LLVMInitializeX86TargetInfo();
		LLVMInitializeX86Target();
		LLVMInitializeX86TargetMC();
		
		import llvm.c.executionEngine;
		LLVMLinkInMCJIT();
		LLVMInitializeX86AsmPrinter();
		
		this.optLevel = optLevel;
		this.linkerParams = linkerParams;
		
		version(OSX) {
			auto triple = "x86_64-apple-darwin9".ptr;
		} else {
			auto triple = "x86_64-pc-linux-gnu".ptr;
		}
		
		targetMachine = LLVMCreateTargetMachine(
			LLVMGetFirstTarget(),
			triple,
			"x86-64".ptr,
			"".ptr,
			LLVMCodeGenOptLevel.Default,
			LLVMRelocMode.Default,
			LLVMCodeModel.Default,
		);
		
		auto td = LLVMCreateTargetDataLayout(targetMachine);
		scope(exit) LLVMDisposeTargetData(td);
		
		pass = new CodeGen(context, scheduler, obj, this, name, td);
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
		foreach(m; modules) {
			pass.visit(m);
		}
		
		import llvm.c.transforms.passManagerBuilder;
		auto pmb = LLVMPassManagerBuilderCreate();
		scope(exit) LLVMPassManagerBuilderDispose(pmb);
		
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
		
		// Dump module for debug purpose.
		// LLVMDumpModule(pass.dmodule);
		
		/+
		import std.stdio;
		writeln("\nASM generated :");
		
		LLVMTargetMachineEmitToFile(
			targetMachine,
			dmodule,
			"/dev/stdout",
			LLVMCodeGenFileType.Assembly,
			&errorPtr,
		);
		// +/
	}

	void emitObject(Module[] modules, string objFile) {
		runLLVMPasses(modules);
		
		import std.string;
		char* errorPtr;
		auto linkError = LLVMTargetMachineEmitToFile(
			targetMachine,
			pass.dmodule,
			objFile.toStringz(),
			LLVMCodeGenFileType.Object,
			&errorPtr,
		);
		
		if (linkError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string, std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			
			assert(0, "Fail to link ! Exiting...");
		}
	}

	void emitAsm(Module[] modules, string filename) {
		runLLVMPasses(modules);

		import std.string;
		char* errorPtr;
		auto printError = LLVMTargetMachineEmitToFile(
			targetMachine,
			pass.dmodule,
			filename.toStringz(),
			LLVMCodeGenFileType.Assembly,
			&errorPtr,
		);
		
		if (printError) {
			scope(exit) LLVMDisposeMessage(errorPtr);

			import std.c.string, std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);

			assert(0, "Failed to output assembly file! Exiting...");
		}
	}

	void emitLLVMAsm(Module[] modules, string filename) {
		runLLVMPasses(modules);

		import std.string;
		char* errorPtr;
		auto printError = LLVMPrintModuleToFile(
			pass.dmodule,
			filename.toStringz(),
			&errorPtr,
		);
		
		if (printError) {
			scope(exit) LLVMDisposeMessage(errorPtr);

			import std.c.string, std.stdio;
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
		import std.process;
		auto linkCommand = "gcc -o "
			~ escapeShellFileName(executable) ~ " "
			~ escapeShellFileName(objFile)
			~ linkerParams ~ " -lsdrt -lphobos -lpthread";
		/+
		import std.stdio;
		writeln(linkCommand);
		// +/
		wait(spawnShell(linkCommand));
	}
}

