module d.llvm.string;

import d.llvm.codegen;

import llvm.c.core;

final class StringGen {
	private CodeGenPass pass;
	alias pass this;

	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	// TODO: refactor that.
	private LLVMValueRef[string] stringLiterals;
	
	auto buildDString(string str) in {
		assert(str.length <= uint.max, "string length must be <= uint.max");
	} body {
		return stringLiterals.get(str, stringLiterals[str] = {
			auto cstr = str ~ '\0';
			auto charArray = LLVMConstStringInContext(pass.llvmCtx, cstr.ptr, cast(uint) cstr.length, true);
			
			auto globalVar = LLVMAddGlobal(pass.dmodule, LLVMTypeOf(charArray), ".str");
			LLVMSetInitializer(globalVar, charArray);
			LLVMSetLinkage(globalVar, LLVMLinkage.Private);
			LLVMSetGlobalConstant(globalVar, true);
			LLVMSetUnnamedAddr(globalVar, true);
			
			LLVMValueRef[2] slice;
			slice[0] = LLVMConstInt(LLVMInt64TypeInContext(pass.llvmCtx), str.length, false);
			
			LLVMValueRef[2] indices = [LLVMConstInt(LLVMInt64TypeInContext(pass.llvmCtx), 0, true), LLVMConstInt(LLVMInt64TypeInContext(pass.llvmCtx), 0, true)];
			slice[1] = LLVMConstInBoundsGEP(globalVar, indices.ptr, 2);
			
			return LLVMConstStructInContext(pass.llvmCtx, slice.ptr, 2, false);
		}());
	}
}
