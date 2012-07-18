module d.backend.llvm;

import d.ast.dmodule;

import llvm.c.Core;
import llvm.c.ExecutionEngine;

interface Backend {
	void codeGen(Module[] mods);
}

class LLVMBackend : Backend {
	this() {
		LLVMLinkInJIT();
		LLVMLinkInInterpreter();
	}
	
	void codeGen(Module[] mods) {
		import d.backend.codegen;
		auto dmodule = codeGen(mods[0]);
		
		// Let's run it !
		import std.stdio;
		
		LLVMExecutionEngineRef ee;
		char* errorPtr;
		int creationResult = LLVMCreateExecutionEngineForModule(&ee, dmodule, &errorPtr);
		if(creationResult) {
			import std.c.string;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			writeln("Cannot create execution engine ! Exiting...");
			return;
		}
		
		LLVMValueRef fun;
		auto found = LLVMFindFunction(ee, cast(char*) "main".ptr, &fun);
		
		auto executionResult = LLVMRunFunction(ee, fun, 0, null);
		auto returned = LLVMGenericValueToInt(executionResult, false);
		
		writeln("returned : ", returned);
	}
}

