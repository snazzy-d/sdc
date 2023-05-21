module d.llvm.runtime;

import d.llvm.expression;
import d.llvm.local;

import d.ir.symbol;

import llvm.c.core;

struct RuntimeData {
private:
	Function sdGCalloc;
	Function sdThrow;
}

struct RuntimeGen {
	private LocalPass pass;
	alias pass this;

	this(LocalPass pass) {
		this.pass = pass;
	}

	private auto getGCallocFunction() {
		if (runtimeData.sdGCalloc) {
			return runtimeData.sdGCalloc;
		}

		auto fun = runtimeData.sdGCalloc = pass.object.getGCalloc();
		LLVMAddAttributeAtIndex(declare(fun), LLVMAttributeReturnIndex,
		                        getAttribute("noalias"));

		return fun;
	}

	auto genGCalloc(LLVMTypeRef type) {
		LLVMValueRef[1] args;
		args[0] = LLVMSizeOf(type);
		return ExpressionGen(pass).buildCall(getGCallocFunction(), args[]);
	}

	private auto getThrowFunction() {
		if (runtimeData.sdThrow) {
			return runtimeData.sdThrow;
		}

		auto fun = runtimeData.sdThrow = pass.object.getThrow();
		LLVMAddAttributeAtIndex(declare(fun), LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	auto genThrow(LLVMValueRef e) {
		LLVMValueRef[1] args;
		args[0] = e;
		return ExpressionGen(pass).buildCall(getThrowFunction(), args[]);
	}
}
