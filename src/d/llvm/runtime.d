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

	LLVMValueRef sdClassDowncast;
	LLVMValueRef sdFinalClassDowncast;

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
		LLVMAddAttributeAtIndex(fun, LLVMAttributeReturnIndex, noAlias);

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
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noReturn);

		return fun;
	}

	auto genThrow(LLVMValueRef e) {
		LLVMValueRef[1] args = [e];
		return ExpressionGen(pass).callGlobal(getThrowFunction(), args);
	}

	private auto getClassDowncast() {
		if (runtimeData.sdClassDowncast) {
			return runtimeData.sdClassDowncast;
		}

		// Make sure we always define class downcast, so it can be inlined.
		auto fun = runtimeData.sdClassDowncast =
			define(pass.object.getClassDowncast());
		LLVMSetLinkage(fun, LLVMLinkage.Private);

		return fun;
	}

	auto genClassDowncast(LLVMValueRef o, LLVMValueRef c) {
		LLVMValueRef[2] args = [o, c];
		return ExpressionGen(pass).callGlobal(getClassDowncast(), args);
	}

	private auto getFinalClassDowncast() {
		if (runtimeData.sdFinalClassDowncast) {
			return runtimeData.sdFinalClassDowncast;
		}

		// Make sure we always define class downcast, so it can be inlined.
		auto fun = runtimeData.sdFinalClassDowncast =
			define(pass.object.getFinalClassDowncast());
		LLVMSetLinkage(fun, LLVMLinkage.Private);

		return fun;
	}

	auto genFinalClassDowncast(LLVMValueRef o, LLVMValueRef c) {
		LLVMValueRef[2] args = [o, c];
		return ExpressionGen(pass).callGlobal(getFinalClassDowncast(), args);
	}

	private auto getAssertFailFunction() {
		if (runtimeData.sdAssertFail) {
			return runtimeData.sdAssertFail;
		}

		auto fun =
			runtimeData.sdAssertFail = declare(pass.object.getAssertFail());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noReturn);
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noUnwind);

		return fun;
	}

	private auto getAssertFailMsgFunction() {
		if (runtimeData.sdAssertFailMsg) {
			return runtimeData.sdAssertFailMsg;
		}

		auto fun = runtimeData.sdAssertFailMsg =
			declare(pass.object.getAssertFailMsg());
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noReturn);
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noUnwind);

		return fun;
	}

	auto genHalt(Location location, LLVMValueRef message) {
		auto floc = location.getFullLocation(context);
		auto line = floc.getStartLineNumber() + 1;

		import d.llvm.constant;
		auto str = ConstantGen(pass.pass)
			.buildDString(floc.getSource().getFileName().toString());
		LLVMValueRef[3] args = [message, str, LLVMConstInt(i32, line, false)];

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
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noReturn);
		LLVMAddAttributeAtIndex(fun, LLVMAttributeFunctionIndex, noUnwind);

		return fun;
	}

	auto genArrayOutOfBounds(Location location) {
		auto floc = location.getFullLocation(context);
		auto line = floc.getStartLineNumber() + 1;

		import d.llvm.constant;
		auto str = ConstantGen(pass.pass)
			.buildDString(floc.getSource().getFileName().toString());
		LLVMValueRef[2] args = [str, LLVMConstInt(i32, line, false)];

		return
			ExpressionGen(pass).callGlobal(getArrayOutOfBoundsFunction(), args);
	}
}
