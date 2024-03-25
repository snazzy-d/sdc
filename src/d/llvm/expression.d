module d.llvm.expression;

import d.llvm.local;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import source.location;

import util.visitor;

import llvm.c.core;

struct ExpressionGen {
	private LocalPass pass;
	alias pass this;

	this(LocalPass pass) {
		this.pass = pass;
	}

	LLVMValueRef visit(Expression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			import source.exception, std.format;
			throw new CompileException(
				e.location, format!"%s is not supported."(typeid(e)));
		})(e);
	}

	LLVMValueRef visit(ConstantExpression e) {
		import d.llvm.constant;
		return ConstantGen(pass.pass).visit(e.value);
	}

	private LLVMValueRef addressOf(E)(E e) if (is(E : Expression))
			in(e.isLvalue, "e must be an lvalue") {
		return AddressOfGen(pass).visit(e);
	}

	private LLVMValueRef buildLoad(LLVMValueRef ptr, LLVMTypeRef type,
	                               TypeQualifier q) {
		auto l = LLVMBuildLoad2(builder, type, ptr, "");
		final switch (q) with (TypeQualifier) {
			case Mutable, Inout, Const:
				break;

			case Shared, ConstShared:
				auto k = LLVMGetTypeKind(type);
				if (k != LLVMTypeKind.Integer && k != LLVMTypeKind.Function
					    && k != LLVMTypeKind.Pointer) {
					import std.format, std.string;
					throw new Exception(
						format!"Cannot generate atomic load for %s"(
							fromStringz(LLVMPrintTypeToString(type))));
				}

				import llvm.c.target;
				LLVMSetAlignment(l, LLVMABIAlignmentOfType(targetData, type));
				LLVMSetOrdering(l, LLVMAtomicOrdering.SequentiallyConsistent);
				break;

			case Immutable:
				// TODO: !invariant.load
				break;
		}

		return l;
	}

	private LLVMValueRef loadAddressOf(E)(E e) if (is(E : Expression))
			in(e.isLvalue, "e must be an lvalue") {
		auto t = e.type.getCanonical();
		return buildLoad(addressOf(e), typeGen.visit(t), t.qualifier);
	}

	private LLVMValueRef buildStore(LLVMValueRef ptr, LLVMValueRef val,
	                                TypeQualifier q) {
		auto s = LLVMBuildStore(builder, val, ptr);
		final switch (q) with (TypeQualifier) {
			case Mutable, Inout, Const:
				break;

			case Shared, ConstShared:
				auto t = LLVMTypeOf(val);
				auto k = LLVMGetTypeKind(t);
				if (k != LLVMTypeKind.Integer && k != LLVMTypeKind.Function
					    && k != LLVMTypeKind.Pointer) {
					import std.format, std.string;
					throw new Exception(
						format!"Cannot generate atomic store for %s"(
							fromStringz(LLVMPrintTypeToString(t))));
				}

				import llvm.c.target;
				LLVMSetAlignment(s, LLVMABIAlignmentOfType(targetData, t));
				LLVMSetOrdering(s, LLVMAtomicOrdering.SequentiallyConsistent);
				break;

			case Immutable:
				// TODO: !invariant.load
				break;
		}

		return s;
	}

	private auto handleBinaryOp(alias LLVMBuildOp)(BinaryExpression e) {
		// XXX: should be useless, but parameters's order of evaluation is bugguy.
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);

		return LLVMBuildOp(builder, lhs, rhs, "");
	}

	private
	auto handleLogicalBinary(bool shortCircuitOnTrue)(BinaryExpression e) {
		auto lhs = visit(e.lhs);

		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);

		static if (shortCircuitOnTrue) {
			auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "or_rhs");
			auto mergeBB =
				LLVMAppendBasicBlockInContext(llvmCtx, fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "and_rhs");
			auto mergeBB =
				LLVMAppendBasicBlockInContext(llvmCtx, fun, "and_merge");
			LLVMBuildCondBr(builder, lhs, rhsBB, mergeBB);
		}

		// Emit rhs
		LLVMPositionBuilderAtEnd(builder, rhsBB);

		auto rhs = visit(e.rhs);

		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);

		// Codegen of lhs can change the current block, so we put everything in order.
		rhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, rhsBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);

		// Generate phi to get the result.
		auto phiNode = LLVMBuildPhi(builder, typeGen.visit(e.type), "");

		LLVMValueRef[2] incomingValues = [lhs, rhs];
		LLVMBasicBlockRef[2] incomingBlocks = [lhsBB, rhsBB];

		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr,
		                incomingValues.length);

		return phiNode;
	}

	LLVMValueRef visit(BinaryExpression e) {
		final switch (e.op) with (BinaryOp) {
			case Comma:
				visit(e.lhs);
				return visit(e.rhs);

			case Assign:
				auto lhs = addressOf(e.lhs);
				auto rhs = visit(e.rhs);

				buildStore(lhs, rhs, e.lhs.type.qualifier);
				return rhs;

			case Add:
				return handleBinaryOp!LLVMBuildAdd(e);

			case Sub:
				return handleBinaryOp!LLVMBuildSub(e);

			case Mul:
				return handleBinaryOp!LLVMBuildMul(e);

			case UDiv:
				return handleBinaryOp!LLVMBuildUDiv(e);

			case SDiv:
				return handleBinaryOp!LLVMBuildSDiv(e);

			case URem:
				return handleBinaryOp!LLVMBuildURem(e);

			case SRem:
				return handleBinaryOp!LLVMBuildSRem(e);

			case Pow:
				assert(0, "Not implemented.");

			case Or:
				return handleBinaryOp!LLVMBuildOr(e);

			case And:
				return handleBinaryOp!LLVMBuildAnd(e);

			case Xor:
				return handleBinaryOp!LLVMBuildXor(e);

			case LeftShift:
				return handleBinaryOp!LLVMBuildShl(e);

			case UnsignedRightShift:
				return handleBinaryOp!LLVMBuildLShr(e);

			case SignedRightShift:
				return handleBinaryOp!LLVMBuildAShr(e);

			case LogicalOr:
				return handleLogicalBinary!true(e);

			case LogicalAnd:
				return handleLogicalBinary!false(e);
		}
	}

	private
	LLVMValueRef handleComparison(ICmpExpression e, LLVMIntPredicate pred) {
		// XXX: should be useless, but parameters's order of evaluation
		// not enforced by DMD.
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);

		return LLVMBuildICmp(builder, pred, lhs, rhs, "");
	}

	private LLVMValueRef handleComparison(
		ICmpExpression e,
		LLVMIntPredicate signedPredicate,
		LLVMIntPredicate unsignedPredicate,
	) {
		auto t = e.lhs.type.getCanonical();
		if (t.kind == TypeKind.Builtin) {
			return handleComparison(
				e, t.builtin.isSigned() ? signedPredicate : unsignedPredicate);
		}

		if (t.kind == TypeKind.Pointer) {
			return handleComparison(e, unsignedPredicate);
		}

		auto t1 = e.lhs.type.toString(context);
		auto t2 = e.rhs.type.toString(context);

		import std.format;
		assert(0, format!"Can't compare %s with %s."(t1, t2));
	}

	LLVMValueRef visit(ICmpExpression e) {
		final switch (e.op) with (ICmpOp) {
			case Equal:
				return handleComparison(e, LLVMIntPredicate.EQ);

			case NotEqual:
				return handleComparison(e, LLVMIntPredicate.NE);

			case GreaterThan:
				return handleComparison(e, LLVMIntPredicate.SGT,
				                        LLVMIntPredicate.UGT);

			case GreaterEqual:
				return handleComparison(e, LLVMIntPredicate.SGE,
				                        LLVMIntPredicate.UGE);

			case SmallerThan:
				return handleComparison(e, LLVMIntPredicate.SLT,
				                        LLVMIntPredicate.ULT);

			case SmallerEqual:
				return handleComparison(e, LLVMIntPredicate.SLE,
				                        LLVMIntPredicate.ULE);
		}
	}

	private LLVMValueRef buildUnary(int Offset, bool IsPost)(Expression e) {
		auto t = e.type.getCanonical();
		auto type = typeGen.visit(t);

		auto ptr = addressOf(e);
		auto value = buildLoad(ptr, type, t.qualifier);
		auto postRet = value;

		if (t.kind == TypeKind.Pointer) {
			auto o = LLVMConstInt(i32, Offset, true);
			auto gepType = typeGen.getElementType(t);
			value = LLVMBuildInBoundsGEP2(builder, gepType, value, &o, 1, "");
		} else {
			auto o = LLVMConstInt(type, Offset, true);
			value = LLVMBuildAdd(builder, value, o, "");
		}

		LLVMBuildStore(builder, value, ptr);
		return IsPost ? postRet : value;
	}

	LLVMValueRef visit(UnaryExpression e) {
		final switch (e.op) with (UnaryOp) {
			case AddressOf:
				return addressOf(e.expr);

			case Dereference:
				auto t = e.type.getCanonical();
				auto type = typeGen.visit(t);
				return buildLoad(visit(e.expr), type, t.qualifier);

			case PreInc:
				return buildUnary!(1, false)(e.expr);

			case PreDec:
				return buildUnary!(-1, false)(e.expr);

			case PostInc:
				return buildUnary!(1, true)(e.expr);

			case PostDec:
				return buildUnary!(-1, true)(e.expr);

			case Plus:
				return visit(e.expr);

			case Minus:
				auto eType = typeGen.visit(e.type);
				return LLVMBuildSub(builder, LLVMConstInt(eType, 0, true),
				                    visit(e.expr), "");

			case Not:
				auto eType = typeGen.visit(e.type);
				return LLVMBuildICmp(
					builder, LLVMIntPredicate.EQ, LLVMConstInt(eType, 0, true),
					visit(e.expr), "");

			case Complement:
				auto eType = typeGen.visit(e.type);
				return LLVMBuildXor(builder, visit(e.expr),
				                    LLVMConstInt(eType, -1, true), "");
		}
	}

	LLVMValueRef visit(TernaryExpression e) {
		auto cond = visit(e.condition);

		auto condBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(condBB);

		auto trueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "if_true");
		auto falseBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "if_false");
		auto mergeBB =
			LLVMAppendBasicBlockInContext(llvmCtx, fun, "ternary_merge");

		LLVMBuildCondBr(builder, cond, trueBB, falseBB);

		// Emit lhs
		LLVMPositionBuilderAtEnd(builder, trueBB);
		auto ifTrue = visit(e.ifTrue);
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);

		// Codegen of lhs can change the current block, so we put everything in order.
		trueBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(falseBB, trueBB);

		// Emit rhs
		LLVMPositionBuilderAtEnd(builder, falseBB);
		auto ifFalse = visit(e.ifFalse);
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);

		// Codegen of rhs can change the current block, so we put everything in order.
		falseBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, falseBB);

		// Generate phi to get the result.
		LLVMPositionBuilderAtEnd(builder, mergeBB);

		auto eType = typeGen.visit(e.type);
		auto phiNode = LLVMBuildPhi(builder, eType, "");

		LLVMValueRef[2] incomingValues = [ifTrue, ifFalse];
		LLVMBasicBlockRef[2] incomingBlocks = [trueBB, falseBB];

		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr,
		                incomingValues.length);

		return phiNode;
	}

	LLVMValueRef visit(VariableExpression e) {
		return (e.var.storage == Storage.Enum || e.var.isFinal)
			? declare(e.var)
			: loadAddressOf(e);
	}

	LLVMValueRef visit(GlobalVariableExpression e) {
		return loadAddressOf(e);
	}

	LLVMValueRef visit(FieldExpression e) {
		if (e.isLvalue) {
			return loadAddressOf(e);
		}

		assert(e.expr.type.kind != TypeKind.Union,
		       "rvalue unions not implemented.");
		return LLVMBuildExtractValue(builder, visit(e.expr), e.field.index, "");
	}

	private static getFunctionType(Type t) {
		return t.getCanonical().asFunctionType();
	}

	private
	LLVMValueRef genMethod(LLVMValueRef dg, Expression[] contexts, Function f) {
		auto m = cast(Method) f;
		if (m is null || m.isFinal) {
			return declare(f);
		}

		// Virtual dispatch.
		assert(m.hasThis);

		auto classType = contexts[m.hasContext].type.getCanonical();
		assert(classType.kind == TypeKind.Class,
		       "Virtual dispatch can only be done on classes!");

		auto c = classType.dclass;
		auto metadata = getClassInfo(c);
		auto mdStruct = LLVMGlobalGetValueType(metadata);

		if (!c.isFinal) {
			auto thisPtr = LLVMBuildExtractValue(builder, dg, m.hasContext, "");
			metadata = loadTypeid(thisPtr);
		}

		auto vtbl = LLVMBuildStructGEP2(builder, mdStruct, metadata, 1, "vtbl");
		auto vtblType = LLVMStructGetTypeAtIndex(mdStruct, 1);
		auto entry = LLVMBuildStructGEP2(builder, vtblType, vtbl, m.index, "");

		return LLVMBuildLoad2(builder, llvmPtr, entry, "");
	}

	LLVMValueRef visit(DelegateExpression e) {
		auto type = getFunctionType(e.type);
		auto tCtxs = type.contexts;
		auto eCtxs = e.contexts;

		auto length = cast(uint) tCtxs.length;
		assert(eCtxs.length == length);

		auto dg = LLVMGetUndef(typeGen.visit(type));

		foreach (size_t idx, c; eCtxs) {
			auto i = cast(uint) idx;
			assert(i == idx);

			auto ctxValue = tCtxs[i].isRef ? addressOf(c) : visit(c);
			dg = LLVMBuildInsertValue(builder, dg, ctxValue, i, "");
		}

		auto m = genMethod(dg, eCtxs, e.method);
		return LLVMBuildInsertValue(builder, dg, m, length, "");
	}

	LLVMValueRef visit(NewExpression e) {
		auto ctor = declare(e.ctor);

		import std.algorithm, std.array;
		auto args = e.arguments.map!(a => visit(a)).array();

		auto ct = e.type.getCanonical();
		bool isClass = ct.kind == TypeKind.Class;
		auto eType = isClass
			? typeGen.getClassStructure(ct.dclass)
			: typeGen.visit(ct.element);

		import d.llvm.runtime;
		auto ptr = RuntimeGen(pass).genGCalloc(eType);

		auto thisArg = visit(e.dinit);
		auto thisType = LLVMTypeOf(LLVMGetFirstParam(ctor));

		bool isRefCtor = LLVMGetTypeKind(thisType) == LLVMTypeKind.Pointer;
		if (isRefCtor) {
			LLVMBuildStore(builder, thisArg, ptr);
			thisArg = ptr;
		}

		args = thisArg ~ args;
		auto obj = callGlobal(ctor, args);
		if (!isRefCtor) {
			LLVMBuildStore(builder, obj, ptr);
		}

		return ptr;
	}

	LLVMValueRef visit(IndexExpression e)
			in(e.isLvalue, "e must be an lvalue") {
		return loadAddressOf(e);
	}

	auto genBoundCheck(Location location, LLVMValueRef condition) {
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));

		auto failBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "bound_fail");
		auto okBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "bound_ok");

		auto br = LLVMBuildCondBr(builder, condition, okBB, failBB);

		// We assume that bound check fail is unlikely.
		LLVMSetMetadata(br, profKindID, unlikelyBranch);

		// Emit bound check fail code.
		LLVMPositionBuilderAtEnd(builder, failBB);

		import d.llvm.runtime;
		RuntimeGen(pass).genArrayOutOfBounds(location);
		LLVMBuildUnreachable(builder);

		// And continue regular program flow.
		LLVMPositionBuilderAtEnd(builder, okBB);
	}

	LLVMValueRef visit(SliceExpression e) {
		auto t = e.sliced.type.getCanonical();
		auto eType = typeGen.getElementType(t);

		LLVMValueRef length, ptr;
		switch (t.kind) with (TypeKind) {
			case Slice:
				auto slice = visit(e.sliced);

				length = LLVMBuildExtractValue(builder, slice, 0, ".length");
				ptr = LLVMBuildExtractValue(builder, slice, 1, ".ptr");
				break;

			case Pointer:
				ptr = visit(e.sliced);
				break;

			case Array:
				length = LLVMConstInt(i64, t.size, false);
				ptr = addressOf(e.sliced);
				break;

			default:
				import std.format;
				assert(
					0,
					format!"Don't know how to slice %s."(
						e.type.toString(context))
				);
		}

		auto first = LLVMBuildZExt(builder, visit(e.first), i64, "");
		auto second = LLVMBuildZExt(builder, visit(e.second), i64, "");

		auto condition =
			LLVMBuildICmp(builder, LLVMIntPredicate.ULE, first, second, "");
		if (length) {
			auto boundCheck = LLVMBuildICmp(builder, LLVMIntPredicate.ULE,
			                                second, length, "");
			condition = LLVMBuildAnd(builder, condition, boundCheck, "");
		}

		genBoundCheck(e.location, condition);

		auto sliceType = typeGen.visit(e.type);
		auto slice = LLVMGetUndef(sliceType);

		auto sub = LLVMBuildSub(builder, second, first, "");
		slice = LLVMBuildInsertValue(builder, slice, sub, 0, "");
		ptr = LLVMBuildInBoundsGEP2(builder, eType, ptr, &first, 1, "");
		slice = LLVMBuildInsertValue(builder, slice, ptr, 1, "");

		return slice;
	}

	// FIXME: This is public because of intrinsic codegen in LocalGen.
	LLVMValueRef buildBitCast(LLVMValueRef v, LLVMTypeRef t) {
		// Short circuit when there is nothing to be done.
		if (LLVMTypeOf(v) == t) {
			return v;
		}

		auto k = LLVMGetTypeKind(t);
		if (k != LLVMTypeKind.Struct) {
			assert(k != LLVMTypeKind.Array);
			return LLVMBuildBitCast(builder, v, t, "");
		}

		auto vt = LLVMTypeOf(v);
		assert(LLVMGetTypeKind(vt) == LLVMTypeKind.Struct);

		auto count = LLVMCountStructElementTypes(t);
		assert(LLVMCountStructElementTypes(vt) == count);

		LLVMTypeRef[] types;
		types.length = count;

		LLVMGetStructElementTypes(t, types.ptr);

		auto ret = LLVMGetUndef(t);
		foreach (i; 0 .. count) {
			ret = LLVMBuildInsertValue(
				builder,
				ret,
				buildBitCast(LLVMBuildExtractValue(builder, v, i, ""),
				             types[i]),
				i,
				""
			);
		}

		return ret;
	}

	// FIXME: This should forward to a template in object.d
	// instead of reimplenting the logic.
	LLVMValueRef buildDownCast(LLVMValueRef value, Class c) {
		auto ctid = getClassInfo(c);

		import d.llvm.runtime;
		return c.isFinal
			? RuntimeGen(pass).genFinalClassDowncast(value, ctid)
			: RuntimeGen(pass).genClassDowncast(value, ctid);
	}

	LLVMValueRef visit(CastExpression e) {
		auto value = visit(e.expr);
		if (e.kind == CastKind.Exact || e.kind == CastKind.Qual) {
			return value;
		}

		auto t = e.type.getCanonical();
		if (e.kind == CastKind.Down) {
			return buildDownCast(value, t.dclass);
		}

		auto type = typeGen.visit(t);

		final switch (e.kind) with (CastKind) {
			case Bit:
				return buildBitCast(value, type);

			case UPad:
				return LLVMBuildZExt(builder, value, type, "");

			case SPad:
				return LLVMBuildSExt(builder, value, type, "");

			case Trunc:
				return LLVMBuildTrunc(builder, value, type, "");

			case IntToPtr:
				return LLVMBuildIntToPtr(builder, value, type, "");

			case PtrToInt:
				return LLVMBuildPtrToInt(builder, value, type, "");

			case IntToBool:
				return LLVMBuildICmp(
					builder, LLVMIntPredicate.NE, value,
					LLVMConstInt(LLVMTypeOf(value), 0, false), "");

			case FloatTrunc:
				return LLVMBuildFPTrunc(builder, value, type, "");

			case FloatExtend:
				return LLVMBuildFPExt(builder, value, type, "");

			case FloatToSigned:
				return LLVMBuildFPToSI(builder, value, type, "");

			case FloatToUnsigned:
				return LLVMBuildFPToUI(builder, value, type, "");

			case SignedToFloat:
				return LLVMBuildSIToFP(builder, value, type, "");

			case UnsignedToFloat:
				return LLVMBuildUIToFP(builder, value, type, "");

			case Exact, Qual, Down:
				assert(0, "Unreachable");

			case Invalid:
				assert(0, "Invalid cast");
		}
	}

	LLVMValueRef visit(ArrayLiteral e) {
		auto t = e.type;
		auto count = cast(uint) e.values.length;

		auto eType = typeGen.visit(t.element);
		auto type = LLVMArrayType(eType, count);
		auto array = LLVMGetUndef(type);

		uint i = 0;
		import std.algorithm;
		foreach (v; e.values.map!(v => visit(v))) {
			array = LLVMBuildInsertValue(builder, array, v, i++, "");
		}

		if (t.kind == TypeKind.Array) {
			return array;
		}

		auto ptr = llvmNull;
		if (count > 0) {
			// We have a slice, we need to allocate.
			import d.llvm.runtime;
			ptr = RuntimeGen(pass).genGCalloc(type);

			// Store all the values on heap.
			LLVMBuildStore(builder, array, ptr);
		}

		// Build the slice.
		auto slice = LLVMGetUndef(llvmSlice);
		auto llvmCount = LLVMConstInt(i64, count, false);
		slice = LLVMBuildInsertValue(builder, slice, llvmCount, 0, "");
		slice = LLVMBuildInsertValue(builder, slice, ptr, 1, "");

		return slice;
	}

	LLVMValueRef buildCall(Function f, LLVMValueRef[] args) {
		return callGlobal(declare(f), args);
	}

	auto callGlobal(LLVMValueRef fun, LLVMValueRef[] args) {
		auto type = LLVMGlobalGetValueType(fun);
		return buildCall(fun, type, args);
	}

	auto buildCall(LLVMValueRef callee, LLVMTypeRef type, LLVMValueRef[] args) {
		// Check if we need to invoke.
		if (!lpBB) {
			return LLVMBuildCall2(builder, type, callee, args.ptr,
			                      cast(uint) args.length, "");
		}

		auto currentBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(currentBB);
		auto thenBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "then");
		auto ret = LLVMBuildInvoke2(builder, type, callee, args.ptr,
		                            cast(uint) args.length, thenBB, lpBB, "");

		LLVMMoveBasicBlockAfter(thenBB, currentBB);
		LLVMPositionBuilderAtEnd(builder, thenBB);

		return ret;
	}

	private LLVMValueRef buildCall(CallExpression c) {
		auto cType = getFunctionType(c.callee.type);
		auto contexts = cType.contexts;
		auto params = cType.parameters;

		LLVMValueRef[] args;
		args.length = contexts.length + c.arguments.length;

		auto callee = visit(c.callee);
		foreach (i, ctx; contexts) {
			args[i] = LLVMBuildExtractValue(builder, callee, cast(uint) i, "");
		}

		auto firstarg = contexts.length;
		if (firstarg) {
			callee = LLVMBuildExtractValue(builder, callee,
			                               cast(uint) contexts.length, "");
		}

		uint i = 0;
		foreach (t; params) {
			args[i + firstarg] =
				t.isRef ? addressOf(c.arguments[i]) : visit(c.arguments[i]);
			i++;
		}

		// Handle variadic functions.
		while (i < c.arguments.length) {
			args[i + firstarg] = visit(c.arguments[i]);
			i++;
		}

		auto type = typeGen.getFunctionType(cType);
		return buildCall(callee, type, args);
	}

	LLVMValueRef visit(CallExpression c) {
		auto r = buildCall(c);
		auto isRef = getFunctionType(c.callee.type).returnType.isRef;
		if (!isRef) {
			return r;
		}

		auto returnType = typeGen.visit(c.type);
		return LLVMBuildLoad2(builder, returnType, r, "");
	}

	LLVMValueRef visit(IntrinsicExpression e) {
		import d.llvm.intrinsic;
		return buildBitCast(
			IntrinsicGen(pass).build(e.intrinsic, e.arguments),
			// XXX: This is necessary until returning sequence is supported.
			typeGen.visit(e.type)
		);
	}

	LLVMValueRef visit(TupleExpression e) {
		auto tuple = LLVMGetUndef(typeGen.visit(e.type));

		uint i = 0;
		import std.algorithm;
		foreach (v; e.values.map!(v => visit(v))) {
			tuple = LLVMBuildInsertValue(builder, tuple, v, i++, "");
		}

		return tuple;
	}

	private LLVMValueRef loadTypeid(LLVMValueRef value) {
		return LLVMBuildLoad2(builder, llvmPtr, value, "");
	}

	LLVMValueRef visit(DynamicTypeidExpression e) {
		auto arg = visit(e.argument);
		auto c = e.argument.type.getCanonical().dclass;
		return c.isFinal ? getClassInfo(c) : loadTypeid(arg);
	}
}

struct AddressOfGen {
	private LocalPass pass;
	alias pass this;

	this(LocalPass pass) {
		this.pass = pass;
	}

	LLVMValueRef visit(Expression e)
			in(e.isLvalue, "You can only compute addresses of lvalues.") {
		return this.dispatch(e);
	}

	private LLVMValueRef valueOf(E)(E e) if (is(E : Expression)) {
		return ExpressionGen(pass).visit(e);
	}

	LLVMValueRef visit(VariableExpression e) in {
		assert(e.var.storage != Storage.Enum, "enum have no address.");
		assert(!e.var.isFinal, "finals have no address.");
	} do {
		return declare(e.var);
	}

	LLVMValueRef visit(GlobalVariableExpression e) {
		return globalGen.declare(e.var);
	}

	LLVMValueRef visit(FieldExpression e) {
		auto base = e.expr;
		auto t = base.type.getCanonical();

		LLVMValueRef ptr;
		LLVMTypeRef type;

		switch (t.kind) with (TypeKind) {
			case Slice, Struct, Union:
				ptr = visit(base);
				type = typeGen.visit(t);
				break;

			// XXX: Remove pointer. libd do not dererefence as expected.
			case Pointer:
				ptr = valueOf(base);
				type = typeGen.getElementType(t);
				break;

			case Class:
				ptr = valueOf(base);
				type = typeGen.getClassStructure(t.dclass);
				break;

			default:
				import std.format;
				assert(
					0,
					format!"Address of field only work on aggregate types, not %s."(
						t.toString(context))
				);
		}

		if (t.kind == TypeKind.Union) {
			return ptr;
		}

		return LLVMBuildStructGEP2(builder, type, ptr, e.field.index, "");
	}

	LLVMValueRef visit(ContextExpression e)
			in(e.type.kind == TypeKind.Context,
			   "ContextExpression must be of ContextType!") {
		return pass.getContext(e.type.context);
	}

	LLVMValueRef visit(
		UnaryExpression e
	) in(e.op == UnaryOp.Dereference, "Only dereferences op are lvalues!") {
		return valueOf(e.expr);
	}

	LLVMValueRef visit(CastExpression e) {
		auto type = typeGen.visit(e.type);
		auto value = visit(e.expr);

		final switch (e.kind) with (CastKind) {
			case Exact, Qual, Bit:
				return value;

			case Invalid, IntToPtr, PtrToInt, Down:
			case IntToBool, Trunc, SPad, UPad:
			case FloatToSigned, FloatToUnsigned:
			case UnsignedToFloat, SignedToFloat:
			case FloatExtend, FloatTrunc:
				assert(0, "Not an lvalue");
		}
	}

	LLVMValueRef visit(CallExpression c) {
		return ExpressionGen(pass).buildCall(c);
	}

	LLVMValueRef visit(IndexExpression e) {
		return computeIndexPtr(e.location, e.indexed, e.index);
	}

	auto computeIndexPtr(Location location, Expression indexed,
	                     Expression index) {
		auto t = indexed.type.getCanonical();
		auto eType = typeGen.getElementType(t);

		LLVMValueRef ptr, length;

		switch (t.kind) with (TypeKind) {
			case Slice:
				auto slice = valueOf(indexed);
				ptr = LLVMBuildExtractValue(builder, slice, 1, ".ptr");
				length = LLVMBuildExtractValue(builder, slice, 0, ".length");
				break;

			case Pointer:
				ptr = valueOf(indexed);
				break;

			case Array:
				ptr = visit(indexed);
				length = LLVMConstInt(i64, t.size, false);
				break;

			default:
				import std.format;
				assert(
					0,
					format!"%s is not an indexable type!"(
						indexed.type.toString(context))
				);
		}

		auto i = valueOf(index);
		if (length) {
			auto zi = LLVMBuildZExt(builder, i, i64, "");
			auto condition =
				LLVMBuildICmp(builder, LLVMIntPredicate.ULT, zi, length, "");
			genBoundCheck(location, condition);
		}

		return LLVMBuildInBoundsGEP2(builder, eType, ptr, &i, 1, "");
	}

	auto genBoundCheck(Location location, LLVMValueRef condition) {
		return ExpressionGen(pass).genBoundCheck(location, condition);
	}
}
