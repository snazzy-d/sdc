module d.llvm.datalayout;

import d.llvm.codegen;

import d.ir.type;

import d.semantic.datalayout;

import llvm.c.target;

final class LLVMDataLayout : DataLayout {
	private CodeGen pass;
	alias pass this;

	this(CodeGen pass) {
		this.pass = pass;
	}

	uint getSize(Type t) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(t);
		return cast(uint) LLVMABISizeOfType(targetData, type);
	}

	uint getAlign(Type t) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(t);
		return LLVMABIAlignmentOfType(targetData, type);
	}
}
