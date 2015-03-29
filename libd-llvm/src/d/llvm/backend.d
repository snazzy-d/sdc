module d.llvm.backend;

import d.llvm.codegen;
import d.llvm.evaluator;

import d.ir.symbol;

import d.context;

import llvm.c.core;
import llvm.c.executionEngine;
import llvm.c.target;
import llvm.c.targetMachine;

import llvm.c.transforms.passManagerBuilder;

import std.array;
import std.process;
import std.stdio;
import std.string;

final class LLVMBackend {
	private CodeGenPass pass;
	private LLVMEvaluator evaluator;
	
	private uint optLevel;
	private string linkerParams;
	
	this(Context context, string name, uint optLevel, string linkerParams) {
		LLVMInitializeX86TargetInfo();
		LLVMInitializeX86Target();
		LLVMInitializeX86TargetMC();
		
		LLVMLinkInMCJIT();
		LLVMInitializeX86AsmPrinter();
		
		this.optLevel = optLevel;
		this.linkerParams = linkerParams;
		
		pass = new CodeGenPass(context, name);
		evaluator = new LLVMEvaluator(pass);
	}
	
	auto getPass() {
		return pass;
	}
	
	auto getEvaluator() {
		return evaluator;
	}
	
	void visit(Module mod) {
		pass.visit(mod);
	}
	
	void visit(Function f) {
		pass.visit(f);
	}
	
	void emitObject(Module[] modules, string objFile) {
		foreach(m; modules) {
			visit(m);
		}
		
		auto dmodule = pass.dmodule;
		
		auto pmb = LLVMPassManagerBuilderCreate();
		scope(exit) LLVMPassManagerBuilderDispose(pmb);
		
		if(optLevel == 0) {
			LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 0);
			LLVMPassManagerBuilderSetOptLevel(pmb, 0);
		} else {
			LLVMDumpModule(dmodule);
			writeln("\n; Optimized as :");
			
			LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 100);
			LLVMPassManagerBuilderSetOptLevel(pmb, optLevel);
		}
		
		auto pm = LLVMCreatePassManager();
		scope(exit) LLVMDisposePassManager(pm);
		
		version(OSX) {
			auto triple = "x86_64-apple-darwin9".ptr;
		} else {
			auto triple = "x86_64-pc-linux-gnu".ptr;
		}
		
		auto targetMachine = LLVMCreateTargetMachine(LLVMGetFirstTarget(), triple, "x86-64".ptr, "".ptr, LLVMCodeGenOptLevel.Default, LLVMRelocMode.Default, LLVMCodeModel.Default);
		scope(exit) LLVMDisposeTargetMachine(targetMachine);

		auto targetData = LLVMGetTargetMachineData(targetMachine);
		LLVMAddTargetData(targetData, pm);
		LLVMPassManagerBuilderPopulateModulePassManager(pmb, pm);
		LLVMRunPassManager(pm, dmodule);
		
		// Dump module for debug purpose.
		LLVMDumpModule(dmodule);
		
		/*
		writeln("\nASM generated :");
		
		LLVMTargetMachineEmitToFile(targetMachine, dmodule, "/dev/stdout".ptr, LLVMCodeGenFileType.Assembly, &errorPtr);
		//*/
		/+
		version(linux) {
			// Hack around the need of _tlsstart and _tlsend.
			auto _tlsstart = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsstart");
			LLVMSetInitializer(_tlsstart, LLVMConstInt(LLVMInt32Type(), 0, true));
			LLVMSetSection(_tlsstart, ".tdata");
			LLVMSetLinkage(_tlsstart, LLVMLinkage.LinkOnceODR);
			
			auto _tlsend = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsend");
			LLVMSetInitializer(_tlsend, LLVMConstInt(LLVMInt32Type(), 0, true));
			LLVMSetThreadLocal(_tlsend, true);
			LLVMSetLinkage(_tlsend, LLVMLinkage.LinkOnceODR);
		}
		// +/
		char* errorPtr;
		auto linkError = LLVMTargetMachineEmitToFile(targetMachine, dmodule, toStringz(objFile), LLVMCodeGenFileType.Object, &errorPtr);
		if(linkError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			
			assert(0, "Fail to link ! Exiting...");
		}
	}
	
	void link(string objFile, string executable) {
		auto linkCommand = "gcc -o " ~ escapeShellFileName(executable) ~ " " ~ escapeShellFileName(objFile) ~ linkerParams ~ " -lsdrt";
		
		writeln(linkCommand);
		wait(spawnShell(linkCommand));
	}
}

