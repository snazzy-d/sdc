module d.llvm.engine;

import llvm.c.core;
import llvm.c.executionEngine;

auto createExecutionEngine(LLVMModuleRef dmodule) {
	char* errorPtr;
	LLVMExecutionEngineRef ee;
	if (!LLVMCreateMCJITCompilerForModule(&ee, dmodule, null, 0, &errorPtr)) {
		return ee;
	}

	scope(exit) LLVMDisposeMessage(errorPtr);

	import core.stdc.string;
	auto error = errorPtr[0 .. strlen(errorPtr)].idup;
	throw new Exception(error);
}

void destroyExecutionEngine(LLVMExecutionEngineRef ee, LLVMModuleRef dmodule) {
	char* errorPtr;
	LLVMModuleRef outMod;
	if (!LLVMRemoveModule(ee, dmodule, &outMod, &errorPtr)) {
		LLVMDisposeExecutionEngine(ee);
		return;
	}

	scope(exit) LLVMDisposeMessage(errorPtr);

	import core.stdc.string;
	auto error = errorPtr[0 .. strlen(errorPtr)].idup;
	throw new Exception(error);
}
