module d.backend.llvm;

import d.ast.symbol;

import llvm.c.Core;
import llvm.c.ExecutionEngine;
import llvm.c.Target;
import llvm.Ext;

interface Backend {
	void codeGen(ModuleSymbol[] mods);
}

class LLVMBackend : Backend {
	this() {
		LLVMInitializeNativeTarget();
		LLVMLinkInJIT();
		
		LLVMInitializeX86AsmPrinter();
	}
	
	void codeGen(ModuleSymbol[] mods) {
		foreach(mod; mods) {
			import d.backend.codegen;
			import std.stdio;
			
			auto dmodule = codeGen(mod);
			
			// Let's run it !
			LLVMExecutionEngineRef ee;
			char* errorPtr;
			auto creationError = LLVMCreateExecutionEngineForModule(&ee, dmodule, &errorPtr);
			if(creationError) {
				import std.c.string;
				writeln(errorPtr[0 .. strlen(errorPtr)]);
				writeln("Cannot create execution engine ! Exiting...");
				return;
			}
			
			LLVMValueRef fun;
			auto notFound = LLVMFindFunction(ee, cast(char*) "_Dmain".ptr, &fun);
			if(notFound) {
				writeln("No main, no gain.");
				return;
			}
			
			/*
			auto fpm = LLVMCreatePassManager();
			LLVMAddTargetData(LLVMGetExecutionEngineTargetData(ee), fpm);
			
			import llvm.c.transforms.Scalar;
			LLVMAddPromoteMemoryToRegisterPass(fpm);
			LLVMAddBasicAliasAnalysisPass(fpm);
			LLVMAddReassociatePass(fpm);
			LLVMAddInstructionCombiningPass(fpm);
			LLVMAddGVNPass(fpm);
			LLVMAddCFGSimplificationPass(fpm);
			
			LLVMRunPassManager (fpm, dmodule);
			//*/
			
			LLVMDumpModule(dmodule);
			
			auto executionResult = LLVMRunFunction(ee, fun, 0, null);
			auto returned = cast(int) LLVMGenericValueToInt(executionResult, true);
			
			writeln("\nreturned : ", returned);
			
			/*
			writeln("\nASM generated :");
			char* foobar = null;
			auto targetMachine = LLVMCreateTargetMachine(cast(char*) "x86-64".ptr, LLVMGetHostTriple(), &foobar, 0, false);
			
			LLVMWriteNativeAsmToFile(targetMachine, dmodule, cast(char*) "/dev/stdout".ptr, 1);
			//*/
			
			/*
			import sdc.util;
			import std.string;
			import std.process;
			
			auto asAssembly = temporaryFilename(".s");
			auto asObject   = temporaryFilename(".o");
			
			// Hack around the need of _tlsstart and _tlsend.
			auto _tlsstart = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsstart");
			LLVMSetInitializer(_tlsstart, LLVMConstInt(LLVMInt32Type(), 0, true));
			LLVMSetSection(_tlsstart, ".tdata");
			
			auto _tlsend = LLVMAddGlobal(dmodule, LLVMInt32Type(), "_tlsend");
			LLVMSetInitializer(_tlsend, LLVMConstInt(LLVMInt32Type(), 0, true));
			LLVMSetThreadLocal(_tlsend, true);
			
			LLVMWriteNativeAsmToFile(targetMachine, dmodule, cast(char*) toStringz(asAssembly), 1);
			
			auto compileCommand = "gcc -c -o " ~ asObject ~ " " ~ asAssembly;
			writeln(compileCommand);
			system(compileCommand);
			
			auto linkCommand = "gcc -o " ~ mod.location.filename ~ ".bin " ~ asObject ~ " -L/opt/gdc/lib64 -lgphobos2 -lpthread -lrt";
			writeln(linkCommand);
			system(linkCommand);
			//*/
		}
	}
}

