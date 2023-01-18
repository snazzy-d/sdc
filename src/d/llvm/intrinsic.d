module d.llvm.intrinsic;

import d.llvm.local;

import source.name;

import d.ir.expression;

import llvm.c.core;

struct IntrinsicGenData {
private:
	LLVMValueRef[Name] cache;
}

struct IntrinsicGen {
	private LocalPass pass;
	alias pass this;

	this(LocalPass pass) {
		this.pass = pass;
	}

	private @property ref LLVMValueRef[Name] cache() {
		return intrinsicGenData.cache;
	}

	LLVMValueRef build(Intrinsic i, Expression[] args) {
		import d.llvm.expression, std.algorithm, std.range;
		return build(i, args.map!(a => ExpressionGen(pass).visit(a)).array());
	}

	LLVMValueRef build(Intrinsic i, LLVMValueRef[] args) {
		final switch (i) with (Intrinsic) {
			case None:
				assert(0, "invalid intrinsic");

			case Expect:
				return expect(args);

			case CompareAndSwap:
				return cas(false, args);

			case CompareAndSwapWeak:
				return cas(true, args);

			case PopCount:
				return ctpop(args);

			case CountLeadingZeros:
				return ctlz(args);

			case CountTrailingZeros:
				return cttz(args);

			case ByteSwap:
				return bswap(args);
		}
	}

	LLVMValueRef expect(LLVMValueRef[] args)
			in(args.length == 2, "Invalid argument count") {
		return expect(args[0], args[1]);
	}

	LLVMValueRef expect(LLVMValueRef v, LLVMValueRef e) {
		LLVMValueRef[2] args = [v, e];
		auto fun = getExpect();
		auto t = LLVMGlobalGetValueType(fun);
		return LLVMBuildCall2(builder, t, fun, args.ptr, args.length, "");
	}

	auto getExpect() {
		auto name = context.getName("llvm.expect.i1");
		if (auto fPtr = name in cache) {
			return *fPtr;
		}

		auto i1 = LLVMInt1TypeInContext(llvmCtx);
		LLVMTypeRef[2] params = [i1, i1];

		auto type = LLVMFunctionType(i1, params.ptr, params.length, false);
		return cache[name] =
			LLVMAddFunction(dmodule, name.toStringz(context), type);
	}

	LLVMValueRef cas(bool weak, LLVMValueRef[] args)
			in(args.length == 3, "Invalid argument count") {
		auto i = cas(weak, args[0], args[1], args[2],
		             LLVMAtomicOrdering.SequentiallyConsistent);
		LLVMSetWeak(i, weak);
		return i;
	}

	LLVMValueRef cas(bool weak, LLVMValueRef ptr, LLVMValueRef old,
	                 LLVMValueRef val, LLVMAtomicOrdering ordering) {
		auto i = LLVMBuildAtomicCmpXchg(builder, ptr, old, val, ordering,
		                                ordering, false);
		LLVMSetWeak(i, weak);
		return i;
	}

	LLVMValueRef ctpop(LLVMValueRef[] args)
			in(args.length == 1, "Invalid argument count") {
		return ctpop(args[0]);
	}

	LLVMValueRef ctpop(LLVMValueRef n) {
		auto bits = LLVMGetIntTypeWidth(LLVMTypeOf(n));
		auto fun = getCtpop(bits);
		auto t = LLVMGlobalGetValueType(fun);
		return LLVMBuildCall2(builder, t, fun, &n, 1, "");
	}

	auto getCtpop(uint bits) {
		import std.conv;
		auto name = context.getName("llvm.ctpop.i" ~ to!string(bits));
		if (auto fPtr = name in cache) {
			return *fPtr;
		}

		return cache[name] = LLVMAddFunction(dmodule, name.toStringz(context),
		                                     getFunctionType(bits));
	}

	LLVMValueRef ctlz(LLVMValueRef[] args)
			in(args.length == 1, "Invalid argument count") {
		return ctlz(args[0]);
	}

	LLVMValueRef ctlz(LLVMValueRef n) {
		LLVMValueRef[2] args =
			[n, LLVMConstInt(LLVMInt1TypeInContext(llvmCtx), false, false)];

		auto bits = LLVMGetIntTypeWidth(LLVMTypeOf(n));
		auto fun = getCtlz(bits);
		auto t = LLVMGlobalGetValueType(fun);
		return LLVMBuildCall2(builder, t, fun, args.ptr, args.length, "");
	}

	auto getCtlz(uint bits) {
		import std.conv;
		auto name = context.getName("llvm.ctlz.i" ~ to!string(bits));
		if (auto fPtr = name in cache) {
			return *fPtr;
		}

		return cache[name] = LLVMAddFunction(dmodule, name.toStringz(context),
		                                     getFunctionTypeWithBool(bits));
	}

	LLVMValueRef cttz(LLVMValueRef[] args)
			in(args.length == 1, "Invalid argument count") {
		return cttz(args[0]);
	}

	LLVMValueRef cttz(LLVMValueRef n) {
		LLVMValueRef[2] args =
			[n, LLVMConstInt(LLVMInt1TypeInContext(llvmCtx), false, false)];

		auto bits = LLVMGetIntTypeWidth(LLVMTypeOf(n));
		auto fun = getCttz(bits);
		auto t = LLVMGlobalGetValueType(fun);
		return LLVMBuildCall2(builder, t, fun, args.ptr, args.length, "");
	}

	auto getCttz(uint bits) {
		import std.conv;
		auto name = context.getName("llvm.cttz.i" ~ to!string(bits));
		if (auto fPtr = name in cache) {
			return *fPtr;
		}

		return cache[name] = LLVMAddFunction(dmodule, name.toStringz(context),
		                                     getFunctionTypeWithBool(bits));
	}

	LLVMValueRef bswap(LLVMValueRef[] args)
			in(args.length == 1, "Invalid argument count") {
		return bswap(args[0]);
	}

	LLVMValueRef bswap(LLVMValueRef n) {
		auto bits = LLVMGetIntTypeWidth(LLVMTypeOf(n));
		auto fun = getBswap(bits);
		auto t = LLVMGlobalGetValueType(fun);
		return LLVMBuildCall2(builder, t, fun, &n, 1, "");
	}

	auto getBswap(uint bits) {
		import std.conv;
		auto name = context.getName("llvm.bswap.i" ~ to!string(bits));
		if (auto fPtr = name in cache) {
			return *fPtr;
		}

		return cache[name] = LLVMAddFunction(dmodule, name.toStringz(context),
		                                     getFunctionType(bits));
	}

private:
	auto getFunctionType(uint bits) {
		auto t = LLVMIntTypeInContext(llvmCtx, bits);
		return LLVMFunctionType(t, &t, 1, false);
	}

	auto getFunctionTypeWithBool(uint bits) {
		auto t = LLVMIntTypeInContext(llvmCtx, bits);
		LLVMTypeRef[2] params = [t, LLVMInt1TypeInContext(llvmCtx)];

		return LLVMFunctionType(t, params.ptr, params.length, false);
	}
}
