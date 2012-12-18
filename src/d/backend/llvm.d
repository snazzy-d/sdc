module d.backend.llvm;

import d.backend.codegen;

import d.ast.dmodule;

import llvm.c.core;
import llvm.c.executionEngine;
import llvm.c.target;
import llvm.c.targetMachine;

import llvm.c.transforms.passManagerBuilder;

import std.array;

interface Backend {
	void codeGen(Module[] mods);
}

final class LLVMBackend : Backend {
	CodeGenPass pass;
	
	this(string name) {
		LLVMInitializeX86TargetInfo();
		LLVMInitializeX86Target();
		LLVMInitializeX86TargetMC();
		
		LLVMLinkInJIT();
		LLVMInitializeX86AsmPrinter();
		
		pass = new CodeGenPass(name);
	}
	
	void codeGen(Module[] mods) {
		import d.backend.codegen;
		import std.stdio;
		
		auto dmodule = pass.visit(mods);
		
		LLVMExecutionEngineRef ee;
		char* errorPtr;
		auto creationError = LLVMCreateJITCompilerForModule(&ee, pass.dmodule, 0, &errorPtr);
		if(creationError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string;
			auto error = errorPtr[0 .. strlen(errorPtr)].idup;
			
			import std.stdio;
			writeln(error);
			writeln("Cannot create execution engine ! Exiting...");
			
			assert(0);
		}
		
		auto pmb = LLVMPassManagerBuilderCreate();
		
		//*
		LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 0);
		LLVMPassManagerBuilderSetOptLevel(pmb, 0);
		/*/
		LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 100);
		LLVMPassManagerBuilderSetOptLevel(pmb, 3);
		//*/
		
		auto pm = LLVMCreatePassManager();
		LLVMPassManagerBuilderPopulateModulePassManager(pmb, pm);
		LLVMAddTargetData(LLVMGetExecutionEngineTargetData(ee), pm);
		
		LLVMRunPassManager(pm, dmodule);
		
		// Dump module for debug purpose.
		LLVMDumpModule(dmodule);
		
		auto targetMachine = LLVMCreateTargetMachine(LLVMGetFirstTarget(), "x86_64-pc-linux-gnu".ptr, "x86-64".ptr, "".ptr, LLVMCodeGenOptLevel.Default, LLVMRelocMode.Default, LLVMCodeModel.Default);
		
		/*
		writeln("\nASM generated :");
		
		LLVMTargetMachineEmitToFile(targetMachine, dmodule, "/dev/stdout".ptr, LLVMCodeGenFileType.Assembly, &errorPtr);
		//*/
		
		//*
		import sdc.util;
		import std.string;
		import std.process;
		
		auto asObject = temporaryFilename(".o");
		
		// Hack around the need of _tlsstart and _tlsend.
		auto _tlsstart = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsstart");
		LLVMSetInitializer(_tlsstart, LLVMConstInt(LLVMInt32Type(), 0, true));
		LLVMSetSection(_tlsstart, ".tdata");
		
		auto _tlsend = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsend");
		LLVMSetInitializer(_tlsend, LLVMConstInt(LLVMInt32Type(), 0, true));
		LLVMSetThreadLocal(_tlsend, true);
		
		LLVMTargetMachineEmitToFile(targetMachine, dmodule, toStringz(asObject), LLVMCodeGenFileType.Object, &errorPtr);
		
		auto linkCommand = "gcc -o " ~ mods.back.location.filename ~ ".bin " ~ asObject ~ " -L/opt/gdc/lib64 -lgphobos2 -lpthread -lrt";
		writeln(linkCommand);
		system(linkCommand);
		//*/
	}
}

