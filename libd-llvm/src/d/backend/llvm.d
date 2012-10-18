module d.backend.llvm;

import d.ast.dmodule;

import llvm.c.core;
import llvm.c.executionEngine;
import llvm.c.target;
import llvm.c.targetMachine;

import llvm.c.transforms.passManagerBuilder;

import std.array;

// In order to JIT.
extern(C) void _d_assert();

interface Backend {
	void codeGen(Module[] mods);
}

class LLVMBackend : Backend {
	this() {
		LLVMInitializeX86TargetInfo();
		LLVMInitializeX86Target();
		LLVMInitializeX86TargetMC();
		
		LLVMLinkInJIT();
		LLVMInitializeX86AsmPrinter();
	}
	
	void codeGen(Module[] mods) {
		import d.backend.codegen;
		import std.stdio;
		
		auto dmodule = codeGen(mods);
		
		LLVMExecutionEngineRef ee;
		char* errorPtr;
		auto creationError = LLVMCreateJITCompilerForModule(&ee, dmodule, 0, &errorPtr);
		if(creationError) {
			import std.c.string;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			writeln("Cannot create execution engine ! Exiting...");
			return;
		}
		
		auto pmb = LLVMPassManagerBuilderCreate();
		LLVMPassManagerBuilderUseInlinerWithThreshold(pmb, 100);
		LLVMPassManagerBuilderSetOptLevel(pmb, 0);
		
		auto pm = LLVMCreatePassManager();
		LLVMPassManagerBuilderPopulateModulePassManager(pmb, pm);
		LLVMAddTargetData(LLVMGetExecutionEngineTargetData(ee), pm);
		
		LLVMRunPassManager(pm, dmodule);
		
		// Dump module for debug purpose.
		LLVMDumpModule(dmodule);
		
		//*
		// Let's run it !
		LLVMValueRef fun;
		if(LLVMFindFunction(ee, "_d_assert".ptr, &fun)) {
			LLVMAddGlobalMapping(ee, fun, &_d_assert);
		}
		
		auto notFound = LLVMFindFunction(ee, "_Dmain".ptr, &fun);
		if(notFound) {
			writeln("No main, no gain.");
			return;
		}
		
		auto executionResult = LLVMRunFunction(ee, fun, 0, null);
		auto returned = cast(int) LLVMGenericValueToInt(executionResult, true);
		
		writeln("\nreturned : ", returned);
		//*/
		
		auto targetMachine = LLVMCreateTargetMachine(LLVMGetFirstTarget(), "x86_64-pc-linux-gnu".ptr, "x86-64".ptr, "".ptr, LLVMCodeGenOptLevel.Default, LLVMRelocMode.Default, LLVMCodeModel.Default);
		
		/*
		writeln("\nASM generated :");
		
		LLVMTargetMachineEmitToFile(targetMachine, dmodule, "/dev/stdout".ptr, LLVMCodeGenFileType.Assembly, &errorPtr);
		//*/
		
		//*
		import sdc.util;
		import std.string;
		import std.process;
		
		auto asObject   = temporaryFilename(".o");
		
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

