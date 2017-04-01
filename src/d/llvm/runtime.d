module d.llvm.runtime;

import d.llvm.codegen;

import d.context.name;

import llvm.c.core;

struct RuntimeGenData {
private:
	LLVMValueRef[Name] cache;
}

struct RuntimeGen {
	private CodeGen pass;
	alias pass this;
	
	this(CodeGen pass) {
		this.pass = pass;
	}
	
	private @property
	ref LLVMValueRef[Name] cache() {
		return runtimeGenData.cache;
	}
	
	// While technically an intrinsic, it fits better here.
	auto getEhTypeidFor() {
		auto name = context.getName("llvm.eh.typeid.for");
		if (auto fPtr = name in cache) {
			return *fPtr;
		}
		
		auto i32 = LLVMInt32TypeInContext(llvmCtx);
		auto arg = LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		auto type = LLVMFunctionType(i32, &arg, 1, false);
		
		return cache[name] = LLVMAddFunction(
			dmodule,
			name.toStringz(context),
			type,
		);
	}
}
