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
	CodeGenPass pass;
	
	LLVMEvaluator evaluator;
	LLVMDataLayout dataLayout;
	
	LLVMTargetMachineRef targetMachine;
	
	uint optLevel;
	string linkerParams;
	
public:
	import d.context.context;
	this(Context context, string name, uint optLevel, string linkerParams) {
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
		
		auto td = LLVMGetTargetMachineData(targetMachine);
		
		pass = new CodeGenPass(context, name, td);
		evaluator = new LLVMEvaluator(pass);
		dataLayout = new LLVMDataLayout(pass, td);
	}
	
	~this() {
		LLVMDisposeTargetMachine(targetMachine);
	}
	
	auto getPass() {
		return pass;
	}
	
	auto getEvaluator() {
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
		GlobalGen(pass).visit(f);
	}
	
	void emitObject(Module[] modules, string objFile) {
		foreach(m; modules) {
			pass.visit(m);
		}
		
		auto dmodule = pass.dmodule;
		
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
		
		auto targetData = LLVMGetTargetMachineData(targetMachine);
		LLVMAddTargetData(targetData, pm);
		LLVMPassManagerBuilderPopulateModulePassManager(pmb, pm);
		LLVMRunPassManager(pm, dmodule);
		
		// Dump module for debug purpose.
		// LLVMDumpModule(dmodule);
		
		/*
		import std.stdio;
		writeln("\nASM generated :");
		
		LLVMTargetMachineEmitToFile(targetMachine, dmodule, "/dev/stdout".ptr, LLVMCodeGenFileType.Assembly, &errorPtr);
		//*/

		import std.string;

		char* errorPtr;
		auto linkError = LLVMTargetMachineEmitToFile(targetMachine, dmodule, toStringz(objFile), LLVMCodeGenFileType.Object, &errorPtr);
		if (linkError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string, std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			
			assert(0, "Fail to link ! Exiting...");
		}
	}
	
	void link(string objFile, string executable) {
		import std.process;
		auto linkCommand = "gcc -o " ~ escapeShellFileName(executable) ~ " " ~ escapeShellFileName(objFile) ~ linkerParams ~ " -lsdrt -lpthread";
		
		import std.stdio;
		writeln(linkCommand);
		wait(spawnShell(linkCommand));
	}
}

