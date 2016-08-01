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
	
	auto getAssert() {
		auto name = BuiltinName!"_d_assert";
		if (auto fPtr = name in cache) {
			return *fPtr;
		}
		
		LLVMTypeRef[2] elts;
		elts[0] = LLVMInt64TypeInContext(llvmCtx);
		elts[1] = LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		
		auto str = LLVMStructTypeInContext(
			llvmCtx,
			elts.ptr,
			elts.length,
			false,
		);
		
		LLVMTypeRef[2] args;
		args[0] = str;
		args[1] = LLVMInt32TypeInContext(llvmCtx);
		
		auto ret = LLVMVoidTypeInContext(llvmCtx);
		auto type = LLVMFunctionType(ret, args.ptr, args.length, false);
		
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return cache[name] = LLVMAddFunction(
			dmodule,
			name.toStringz(context),
			type,
		);
	}
	
	auto getAssertMessage() {
		auto name = BuiltinName!"_d_assert_msg";
		if (auto fPtr = name in cache) {
			return *fPtr;
		}
		
		LLVMTypeRef[2] elts;
		elts[0] = LLVMInt64TypeInContext(llvmCtx);
		elts[1] = LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		
		auto str = LLVMStructTypeInContext(
			llvmCtx,
			elts.ptr,
			elts.length,
			false,
		);
		
		LLVMTypeRef[3] args;
		args[0] = str;
		args[1] = str;
		args[2] = LLVMInt32TypeInContext(llvmCtx);
		
		auto ret = LLVMVoidTypeInContext(llvmCtx);
		auto type = LLVMFunctionType(ret, args.ptr, args.length, false);
		
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return cache[name] = LLVMAddFunction(
			dmodule,
			name.toStringz(context),
			type,
		);
	}
	
	auto getArrayBound() {
		auto name = BuiltinName!"_d_arraybounds";
		if (auto fPtr = name in cache) {
			return *fPtr;
		}
		
		LLVMTypeRef[2] elts;
		elts[0] = LLVMInt64TypeInContext(llvmCtx);
		elts[1] = LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		
		auto str = LLVMStructTypeInContext(
			llvmCtx,
			elts.ptr,
			elts.length,
			false,
		);
		
		LLVMTypeRef[2] args;
		args[0] = str;
		args[1] = LLVMInt32TypeInContext(llvmCtx);
		
		auto ret = LLVMVoidTypeInContext(llvmCtx);
		auto type = LLVMFunctionType(ret, args.ptr, args.length, false);
		
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return cache[name] = LLVMAddFunction(
			dmodule,
			name.toStringz(context),
			type,
		);
	}
	
	auto getAllocMemory() {
		auto name = BuiltinName!"_d_allocmemory";
		if (auto fPtr = name in cache) {
			return *fPtr;
		}
		
		auto voidStar = LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		auto arg = LLVMInt64TypeInContext(llvmCtx);
		auto type = LLVMFunctionType(voidStar, &arg, 1, false);
		
		// Trying to get the patch into LLVM
		// LLVMAddReturnAttr(fun, LLVMAttribute.NoAlias);
		return cache[name] = LLVMAddFunction(
			dmodule,
			name.toStringz(context),
			type,
		);
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
