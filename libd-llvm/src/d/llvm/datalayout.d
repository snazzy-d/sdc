module d.llvm.datalayout;

import d.llvm.codegen;

import d.ir.type;

import d.semantic.datalayout;

import llvm.c.target;

class LLVMDataLayout : DataLayout {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMTargetDataRef targetData;
	
	this(CodeGenPass pass, LLVMTargetDataRef targetData) {
		this.pass = pass;
		this.targetData = targetData;
	}
	
	uint getSize(Type t) {
		return cast(uint) LLVMStoreSizeOfType(targetData, visit(t));
	}
	
	uint getAlign(Type t) {
		return LLVMABIAlignmentOfType(targetData, visit(t));
	}
}
