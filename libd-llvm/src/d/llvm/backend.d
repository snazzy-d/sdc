module d.llvm.backend;

import d.llvm.codegen;

import d.ast.dmodule;

import llvm.c.core;
import llvm.c.executionEngine;
import llvm.c.target;
import llvm.c.targetMachine;

import llvm.c.transforms.passManagerBuilder;

import std.array;
import std.process;
import std.stdio;
import std.string;

interface Backend {
	void codeGen(Module mod);
}

final class LLVMBackend : Backend {
	CodeGenPass pass;
	
	uint optLevel;
	
	this(string name, uint optLevel) {
		LLVMInitializeX86TargetInfo();
		LLVMInitializeX86Target();
		LLVMInitializeX86TargetMC();
		
		LLVMLinkInJIT();
		LLVMInitializeX86AsmPrinter();
		
		pass = new CodeGenPass(name);
		
		this.optLevel = optLevel;
	}
	
	void codeGen(Module mod) {
		pass.visit(mod);
		auto dmodule = pass.dmodule;
		
		LLVMExecutionEngineRef ee;
		char* errorPtr;
		auto creationError = LLVMCreateJITCompilerForModule(&ee, pass.dmodule, 0, &errorPtr);
		if(creationError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string;
			auto error = errorPtr[0 .. strlen(errorPtr)].idup;
			
			writeln(error);
			writeln("Cannot create execution engine ! Exiting...");
			
			assert(0);
		}
		
		auto pmb = LLVMPassManagerBuilderCreate();
		
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
		LLVMPassManagerBuilderPopulateModulePassManager(pmb, pm);
		LLVMAddTargetData(LLVMGetExecutionEngineTargetData(ee), pm);
		
		LLVMRunPassManager(pm, dmodule);
		
		// Dump module for debug purpose.
		LLVMDumpModule(dmodule);
	}
	
	void optimize(uint level) {
		
	}
	
	void emitObject(string objFile) {
		
		version(OX) {
			auto triple = "x86_64-apple-darwin9".ptr;
		} else {
			auto triple = "x86_64-pc-linux-gnu".ptr;
		}
		
		auto targetMachine = LLVMCreateTargetMachine(LLVMGetFirstTarget(), triple, "x86-64".ptr, "".ptr, LLVMCodeGenOptLevel.Default, LLVMRelocMode.Default, LLVMCodeModel.Default);
		
		/*
		writeln("\nASM generated :");
		
		LLVMTargetMachineEmitToFile(targetMachine, dmodule, "/dev/stdout".ptr, LLVMCodeGenFileType.Assembly, &errorPtr);
		//*/
		
		auto dmodule = pass.dmodule;
		char* errorPtr;
		
		// Hack around the need of _tlsstart and _tlsend.
		auto _tlsstart = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsstart");
		LLVMSetInitializer(_tlsstart, LLVMConstInt(LLVMInt32Type(), 0, true));
		LLVMSetSection(_tlsstart, ".tdata");
		
		auto _tlsend = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsend");
		LLVMSetInitializer(_tlsend, LLVMConstInt(LLVMInt32Type(), 0, true));
		LLVMSetThreadLocal(_tlsend, true);
		
		auto linkError = LLVMTargetMachineEmitToFile(targetMachine, dmodule, toStringz(objFile), LLVMCodeGenFileType.Object, &errorPtr);
		if(linkError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			
			assert(0, "Fail to link ! Exiting...");
		}
	}
	
	void link(string objFile, string executable) {
		version(OSX) {
			auto linkCommand = "gcc -o " ~ executable ~ " " ~ objFile ~ " -L/usr/share/dmd/lib -lphobos2 -lpthread";
		} else {
			auto linkCommand = "gcc -o " ~ executable ~ " " ~ objFile ~ " -L/opt/gdc/lib64 -lgphobos2 -lpthread -lrt";
		}
		
		writeln(linkCommand);
		system(linkCommand);
	}
}

