module d.llvm.datalayout;

import d.llvm.codegen;

import d.ir.type;

import d.semantic.datalayout;

import llvm.c.target;

final class LLVMDataLayout : DataLayout {
	private CodeGen pass;
	alias pass this;

	private LLVMTargetDataRef targetData;

	this(CodeGen pass, LLVMTargetDataRef targetData) {
		this.pass = pass;
		this.targetData = targetData;
	}

	uint getSize(Type t) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(t);
		return cast(uint) LLVMStoreSizeOfType(targetData, type);
	}

	uint getAlign(Type t) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(t);
		return LLVMABIAlignmentOfType(targetData, type);
	}
}
