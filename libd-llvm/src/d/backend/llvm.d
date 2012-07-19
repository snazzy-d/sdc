module d.backend.llvm;

import d.ast.dmodule;

import llvm.c.Core;
import llvm.c.ExecutionEngine;
import llvm.c.Target;

interface Backend {
	void codeGen(Module[] mods);
}

class LLVMBackend : Backend {
	this() {
		LLVMInitializeNativeTarget2();
		LLVMLinkInJIT();
	}
	
	void codeGen(Module[] mods) {
		import d.backend.codegen;
		auto dmodule = codeGen(mods[0]);
		
		// Let's run it !
		import std.stdio;
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
		auto notFound = LLVMFindFunction(ee, cast(char*) "main".ptr, &fun);
		if(notFound) {
			import std.c.string;
			writeln("No main, no gain.");
			return;
		}
		
		auto executionResult = LLVMRunFunction(ee, fun, 0, null);
		auto returned = cast(int) LLVMGenericValueToInt(executionResult, true);
		
		writeln("returned : ", returned);
	}
}

