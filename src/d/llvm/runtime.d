module d.llvm.runtime;

import d.llvm.expression;
import d.llvm.local;

import d.ir.symbol;

import source.location;

import llvm.c.core;

struct RuntimeData {
private:
	Function sdGCalloc;
	Function sdThrow;

	Function sdAssertFail;
	Function sdAssertFailMsg;
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
		LLVMValueRef[1] args = [LLVMSizeOf(type)];
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
		LLVMValueRef[1] args = [e];
		return ExpressionGen(pass).buildCall(getThrowFunction(), args[]);
	}

	private auto getAssertFailFunction() {
		if (runtimeData.sdAssertFail) {
			return runtimeData.sdAssertFail;
		}

		auto fun = runtimeData.sdAssertFail = pass.object.getAssertFail();
		LLVMAddAttributeAtIndex(declare(fun), LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	private auto getAssertFailMsgFunction() {
		if (runtimeData.sdAssertFailMsg) {
			return runtimeData.sdAssertFailMsg;
		}

		auto fun = runtimeData.sdAssertFailMsg = pass.object.getAssertFailMsg();
		LLVMAddAttributeAtIndex(declare(fun), LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	auto genHalt(Location location, LLVMValueRef message) {
		auto floc = location.getFullLocation(context);

		LLVMValueRef[3] args = [
			message,
			buildDString(floc.getSource().getFileName().toString()),
			LLVMConstInt(LLVMInt32TypeInContext(llvmCtx),
			             floc.getStartLineNumber(), false),
		];

		return message
			? ExpressionGen(pass).buildCall(getAssertFailMsgFunction(), args[])
			: ExpressionGen(pass)
				.buildCall(getAssertFailFunction(), args[1 .. $]);
	}
}
