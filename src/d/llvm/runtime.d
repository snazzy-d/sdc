module d.llvm.runtime;

import d.llvm.local;

import d.ir.symbol;

import llvm.c.core;

struct RuntimeData {
private:
	Function sdGCalloc;
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
		auto size = LLVMSizeOf(type);
		auto args = (&size)[0 .. 1];

		import d.llvm.expression;
		return ExpressionGen(pass).buildCall(getGCallocFunction(), args);
	}
}
