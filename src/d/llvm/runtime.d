module d.llvm.runtime;

import d.llvm.expression;
import d.llvm.local;

import d.ir.symbol;

import source.location;

import llvm.c.core;

struct RuntimeData {
private:
	LLVMValueRef sdGCalloc;
	LLVMValueRef sdThrow;

	LLVMValueRef sdAssertFail;
	LLVMValueRef sdAssertFailMsg;
	LLVMValueRef sdArrayOutOfBounds;
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

		auto fun = runtimeData.sdGCalloc = declare(pass.object.getGCalloc());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeReturnIndex,
		                        getAttribute("noalias"));

		return fun;
	}

	auto genGCalloc(LLVMTypeRef type) {
		LLVMValueRef[1] args = [LLVMSizeOf(type)];
		return ExpressionGen(pass).callGlobal(getGCallocFunction(), args);
	}

	private auto getThrowFunction() {
		if (runtimeData.sdThrow) {
			return runtimeData.sdThrow;
		}

		auto fun = runtimeData.sdThrow = declare(pass.object.getThrow());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	auto genThrow(LLVMValueRef e) {
		LLVMValueRef[1] args = [e];
		return ExpressionGen(pass).callGlobal(getThrowFunction(), args);
	}

	private auto getAssertFailFunction() {
		if (runtimeData.sdAssertFail) {
			return runtimeData.sdAssertFail;
		}

		auto fun =
			runtimeData.sdAssertFail = declare(pass.object.getAssertFail());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	private auto getAssertFailMsgFunction() {
		if (runtimeData.sdAssertFailMsg) {
			return runtimeData.sdAssertFailMsg;
		}

		auto fun = runtimeData.sdAssertFailMsg =
			declare(pass.object.getAssertFailMsg());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	auto genHalt(Location location, LLVMValueRef message) {
		auto floc = location.getFullLocation(context);

		LLVMValueRef[3] args =
			[message, buildDString(floc.getSource().getFileName().toString()),
			 LLVMConstInt(i32, floc.getStartLineNumber(), false), ];

		return message
			? ExpressionGen(pass).callGlobal(getAssertFailMsgFunction(), args)
			: ExpressionGen(pass)
				.callGlobal(getAssertFailFunction(), args[1 .. $]);
	}

	private auto getArrayOutOfBoundsFunction() {
		if (runtimeData.sdArrayOutOfBounds) {
			return runtimeData.sdArrayOutOfBounds;
		}

		auto fun = runtimeData.sdArrayOutOfBounds =
			declare(pass.object.getArrayOutOfBounds());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex,
		                        getAttribute("noreturn"));

		return fun;
	}

	auto genArrayOutOfBounds(Location location) {
		auto floc = location.getFullLocation(context);

		LLVMValueRef[2] args =
			[buildDString(floc.getSource().getFileName().toString()),
			 LLVMConstInt(i32, floc.getStartLineNumber(), false), ];

		return
			ExpressionGen(pass).callGlobal(getArrayOutOfBoundsFunction(), args);
	}
}
