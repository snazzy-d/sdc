module d.llvm.expression;

import d.llvm.codegen;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.exception;
import d.location;

import util.visitor;

import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

struct ExpressionGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			throw new CompileException(e.location, typeid(e).toString() ~ " is not supported");
		})(e);
	}
	
	private LLVMValueRef addressOf(Expression e) {
		auto aog = AddressOfGen(pass);
		return aog.visit(e);
	}
	
	LLVMValueRef visit(BooleanLiteral bl) {
		return LLVMConstInt(pass.visit(bl.type), bl.value, false);
	}
	
	LLVMValueRef visit(IntegerLiteral!true il) {
		return LLVMConstInt(pass.visit(il.type), il.value, true);
	}
	
	LLVMValueRef visit(IntegerLiteral!false il) {
		return LLVMConstInt(pass.visit(il.type), il.value, false);
	}
	
	LLVMValueRef visit(FloatLiteral fl) {
		return LLVMConstReal(pass.visit(fl.type), fl.value);
	}
	
	// XXX: character types in backend ?
	LLVMValueRef visit(CharacterLiteral cl) {
		return LLVMConstInt(pass.visit(cl.type), cl.value[0], false);
	}
	
	LLVMValueRef visit(NullLiteral nl) {
		return LLVMConstNull(pass.visit(nl.type));
	}
	
	LLVMValueRef visit(StringLiteral sl) {
		return buildDString(sl.value);
	}
	
	private auto handleBinaryOp(alias LLVMBuildOp)(BinaryExpression e) {
		// XXX: should be useless, but order of evaluation of parameters is bugguy.
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		
		return LLVMBuildOp(builder, lhs, rhs, "");
	}
	
	private auto handleBinaryOp(alias LLVMSignedBuildOp, alias LLVMUnsignedBuildOp)(BinaryExpression e) {
		return isSigned(e.type.getCanonical().builtin)
			? handleBinaryOp!LLVMSignedBuildOp(e)
			: handleBinaryOp!LLVMUnsignedBuildOp(e);
	}
	
	private auto handleBinaryOpAssign(alias LLVMBuildOp)(BinaryExpression e) {
		auto lhsPtr = addressOf(e.lhs);
		
		auto lhs = LLVMBuildLoad(builder, lhsPtr, "");
		auto rhs = visit(e.rhs);
		
		auto value = LLVMBuildOp(builder, lhs, rhs, "");
		
		LLVMBuildStore(builder, value, lhsPtr);
		
		return value;
	}
	
	private auto handleBinaryOpAssign(alias LLVMSignedBuildOp, alias LLVMUnsignedBuildOp)(BinaryExpression e) {
		return isSigned(e.type.getCanonical().builtin)
			? handleBinaryOpAssign!LLVMSignedBuildOp(e)
			: handleBinaryOpAssign!LLVMUnsignedBuildOp(e);
	}
	
	private LLVMValueRef handleComparaison(BinaryExpression e, LLVMIntPredicate predicate) {
		static LLVMIntPredicate workaround;
		
		auto oldWorkaround = workaround;
		scope(exit) workaround = oldWorkaround;
		
		workaround = predicate;
		
		return handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, workaround, lhs, rhs, name);
		})(e);
	}
	
	private LLVMValueRef handleComparaison(BinaryExpression e, LLVMIntPredicate signedPredicate, LLVMIntPredicate unsignedPredicate) {
		auto t = e.lhs.type.getCanonical();
		if (t.kind == TypeKind.Builtin) {
			if(isSigned(t.builtin)) {
				return handleComparaison(e, signedPredicate);
			} else {
				return handleComparaison(e, unsignedPredicate);
			}
		} else if (t.kind == TypeKind.Pointer) {
			return handleComparaison(e, unsignedPredicate);
		}
		
		assert(0, "Don't know how to compare " ~ /+ e.lhs.type.toString(context) ~ +/" with "/+ ~ e.rhs.type.toString(context) +/);
	}
	
	private auto handleLogicalBinary(bool shortCircuitOnTrue)(BinaryExpression e) {
		auto lhs = visit(e.lhs);
		
		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);
		
		static if(shortCircuitOnTrue) {
			auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "or_rhs");
			auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "and_rhs");
			auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "and_merge");
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
		auto phiNode = LLVMBuildPhi(builder, pass.visit(e.type), "");
		
		LLVMValueRef[2] incomingValues;
		incomingValues[0] = lhs;
		incomingValues[1] = rhs;
		
		LLVMBasicBlockRef[2] incomingBlocks;
		incomingBlocks[0] = lhsBB;
		incomingBlocks[1] = rhsBB;
		
		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr, incomingValues.length);
		
		return phiNode;
	}
	
	LLVMValueRef visit(BinaryExpression e) {
		final switch(e.op) with(BinaryOp) {
			case Comma :
				visit(e.lhs);
				return visit(e.rhs);
			
			case Assign :
				auto lhs = addressOf(e.lhs);
				auto rhs = visit(e.rhs);
				
				LLVMBuildStore(builder, rhs, lhs);
				return rhs;
			
			case Add :
				return handleBinaryOp!LLVMBuildAdd(e);
			
			case Sub :
				return handleBinaryOp!LLVMBuildSub(e);
				
			case Mul :
				return handleBinaryOp!LLVMBuildMul(e);
			
			case Div :
				return handleBinaryOp!(LLVMBuildSDiv, LLVMBuildUDiv)(e);
			
			case Mod :
				return handleBinaryOp!(LLVMBuildSRem, LLVMBuildURem)(e);
			
			case Pow :
				assert(0, "Not implemented");
			
			case Concat :
			case ConcatAssign :
				assert(0, "Not implemented");
			
			case AddAssign :
				return handleBinaryOpAssign!LLVMBuildAdd(e);
			
			case SubAssign :
				return handleBinaryOpAssign!LLVMBuildSub(e);
				
			case MulAssign :
				return handleBinaryOpAssign!LLVMBuildMul(e);
			
			case DivAssign :
				return handleBinaryOpAssign!(LLVMBuildSDiv, LLVMBuildUDiv)(e);
			
			case ModAssign :
				return handleBinaryOpAssign!(LLVMBuildSRem, LLVMBuildURem)(e);
			
			case PowAssign :
				assert(0, "Not implemented");
			
			case LogicalOr :
				return handleLogicalBinary!true(e);
			
			case LogicalAnd :
				return handleLogicalBinary!false(e);
			
			case LogicalOrAssign :
			case LogicalAndAssign :
				assert(0, "Not implemented");
			
			case BitwiseOr :
				return handleBinaryOp!LLVMBuildOr(e);
			
			case BitwiseAnd :
				return handleBinaryOp!LLVMBuildAnd(e);
			
			case BitwiseXor :
				return handleBinaryOp!LLVMBuildXor(e);
			
			case BitwiseOrAssign :
				return handleBinaryOpAssign!LLVMBuildOr(e);
			
			case BitwiseAndAssign :
				return handleBinaryOpAssign!LLVMBuildAnd(e);
			
			case BitwiseXorAssign :
				return handleBinaryOpAssign!LLVMBuildXor(e);
			
			case Equal :
				return handleComparaison(e, LLVMIntPredicate.EQ);
			
			case NotEqual :
				return handleComparaison(e, LLVMIntPredicate.NE);
			
			case Identical :
				return handleComparaison(e, LLVMIntPredicate.EQ);
			
			case NotIdentical :
				return handleComparaison(e, LLVMIntPredicate.NE);
			
			case In :
			case NotIn :
				assert(0, "Not implemented");
			
			case LeftShift :
				return handleBinaryOp!LLVMBuildShl(e);
			
			case SignedRightShift :
				return handleBinaryOp!LLVMBuildAShr(e);
			
			case UnsignedRightShift :
				return handleBinaryOp!LLVMBuildLShr(e);
			
			case LeftShiftAssign :
			case SignedRightShiftAssign :
			case UnsignedRightShiftAssign :
				assert(0, "Not implemented");
			
			case Greater :
				return handleComparaison(e, LLVMIntPredicate.SGT, LLVMIntPredicate.UGT);
			
			case GreaterEqual :
				return handleComparaison(e, LLVMIntPredicate.SGE, LLVMIntPredicate.UGE);
			
			case Less :
				return handleComparaison(e, LLVMIntPredicate.SLT, LLVMIntPredicate.ULT);
			
			case LessEqual :
				return handleComparaison(e, LLVMIntPredicate.SLE, LLVMIntPredicate.ULE);
			
			case LessGreater :
			case LessEqualGreater :
			case UnorderedLess :
			case UnorderedLessEqual :
			case UnorderedGreater :
			case UnorderedGreaterEqual :
			case Unordered :
			case UnorderedEqual :
				assert(0, "Not implemented");
		}
	}
	
	LLVMValueRef visit(UnaryExpression e) {
		final switch(e.op) with(UnaryOp) {
			case AddressOf :
				return addressOf(e.expr);
			
			case Dereference :
				return LLVMBuildLoad(builder, visit(e.expr), "");
			
			case PreInc :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				auto type = LLVMTypeOf(value);
				
				if (LLVMGetTypeKind(type) == LLVMTypeKind.Pointer) {
					auto one = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), 1, true);
					value = LLVMBuildInBoundsGEP(builder, value, &one, 1, "");
				} else {
					value = LLVMBuildAdd(builder, value, LLVMConstInt(type, 1, true), "");
				}
				
				LLVMBuildStore(builder, value, ptr);
				return value;
			
			case PreDec :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				auto type = LLVMTypeOf(value);
				
				if (LLVMGetTypeKind(type) == LLVMTypeKind.Pointer) {
					auto one = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), -1, true);
					value = LLVMBuildInBoundsGEP(builder, value, &one, 1, "");
				} else {
					value = LLVMBuildSub(builder, value, LLVMConstInt(type, 1, true), "");
				}
				
				LLVMBuildStore(builder, value, ptr);
				return value;
			
			case PostInc :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				auto ret = value;
				auto type = LLVMTypeOf(value);
				
				if (LLVMGetTypeKind(type) == LLVMTypeKind.Pointer) {
					auto one = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), 1, true);
					value = LLVMBuildInBoundsGEP(builder, value, &one, 1, "");
				} else {
					value = LLVMBuildAdd(builder, value, LLVMConstInt(type, 1, true), "");
				}
				
				LLVMBuildStore(builder, value, ptr);
				return ret;
			
			case PostDec :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				auto ret = value;
				auto type = LLVMTypeOf(value);
				
				if (LLVMGetTypeKind(type) == LLVMTypeKind.Pointer) {
					auto one = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), -1, true);
					value = LLVMBuildInBoundsGEP(builder, value, &one, 1, "");
				} else {
					value = LLVMBuildSub(builder, value, LLVMConstInt(type, 1, true), "");
				}
				
				LLVMBuildStore(builder, value, ptr);
				return ret;
			
			case Plus :
				return visit(e.expr);
			
			case Minus :
				return LLVMBuildSub(builder, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expr), "");
			
			case Not :
				return LLVMBuildICmp(builder, LLVMIntPredicate.EQ, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expr), "");
			
			case Complement :
				return LLVMBuildXor(builder, visit(e.expr), LLVMConstInt(pass.visit(e.type), -1, true), "");
		}
	}

	LLVMValueRef visit(TernaryExpression e) {
		auto cond = visit(e.condition);
		
		auto condBB  = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(condBB);
		
		auto lhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "ternary_lhs");
		auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "ternary_rhs");
		auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "ternary_merge");
		
		LLVMBuildCondBr(builder, cond, lhsBB, rhsBB);
		
		// Emit lhs
		LLVMPositionBuilderAtEnd(builder, lhsBB);
		auto lhs = visit(e.lhs);
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of lhs can change the current block, so we put everything in order.
		lhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(lhsBB, rhsBB);
		
		// Emit rhs
		LLVMPositionBuilderAtEnd(builder, rhsBB);
		auto rhs = visit(e.rhs);
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of rhs can change the current block, so we put everything in order.
		rhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, rhsBB);
		
		// Generate phi to get the result.
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		auto phiNode = LLVMBuildPhi(builder, pass.visit(e.type), "");
		
		LLVMValueRef[2] incomingValues;
		incomingValues[0] = lhs;
		incomingValues[1] = rhs;
		
		LLVMBasicBlockRef[2] incomingBlocks;
		incomingBlocks[0] = lhsBB;
		incomingBlocks[1] = rhsBB;
		
		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr, incomingValues.length);
		
		return phiNode;
	}
	
	LLVMValueRef visit(ThisExpression e) {
		assert(thisPtr, "No this pointer");
		return e.isLvalue ? LLVMBuildLoad(builder, thisPtr, "") : thisPtr;
	}
	
	LLVMValueRef visit(VariableExpression e) {
		return (e.var.storage == Storage.Enum)
			? pass.visit(e.var)
			: LLVMBuildLoad(builder, addressOf(e), "");
	}
	
	LLVMValueRef visit(FieldExpression e) {
		if(e.isLvalue) {
			return LLVMBuildLoad(builder, addressOf(e), "");
		}
		
		return LLVMBuildExtractValue(builder, visit(e.expr), e.field.index, "");
	}
	
	LLVMValueRef visit(FunctionExpression e) {
		return pass.visit(e.fun);
	}
	
	LLVMValueRef visit(MethodExpression e) {
		auto type = e.type.getCanonical().asFunctionType();
		auto contexts = type.contexts;
		
		assert(contexts.length == 1, "Multiple contexts not implemented.");
		auto ctxValue = contexts[0].isRef
			? addressOf(e.expr)
			: visit(e.expr);
		
		LLVMValueRef fun;
		if(auto m = cast(Method) e.method) {
			assert(e.expr.type.getCanonical().dclass, "Virtual dispatch can only be done on classes.");
			
			auto vtbl = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, ctxValue, 0, ""), "vtbl");
			fun = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, vtbl, m.index, ""), "");
		} else {
			fun = pass.visit(e.method);
		}
		
		auto dg = LLVMGetUndef(pass.visit(type));
		dg = LLVMBuildInsertValue(builder, dg, fun, 0, "");
		dg = LLVMBuildInsertValue(builder, dg, ctxValue, 1, "");
		
		return dg;
	}
	
	LLVMValueRef visit(NewExpression e) {
		auto ctor = visit(e.ctor);
		auto args = e.args.map!(a => visit(a)).array();
		
		auto type = pass.visit(e.type);
		LLVMValueRef size = LLVMSizeOf(type);
		
		auto alloc = buildCall(druntimeGen.getAllocMemory(), [size]);
		auto ptr = LLVMBuildPointerCast(builder, alloc, type, "");
		LLVMAddInstrAttribute(alloc, 0, LLVMAttribute.NoAlias);
		
		auto thisArg = visit(e.dinit);
		auto thisType = LLVMTypeOf(LLVMGetFirstParam(ctor));
		bool isClass = LLVMGetTypeKind(thisType) == LLVMTypeKind.Pointer;
		if (isClass) {
			auto thisPtr = LLVMBuildBitCast(builder, ptr, LLVMPointerType(LLVMTypeOf(thisArg), 0), "");
			LLVMBuildStore(builder, thisArg, thisPtr);
			thisArg = LLVMBuildBitCast(builder, ptr, thisType, "");
		}
		
		args = thisArg ~ args;
		auto obj = buildCall(ctor, args);
		if (!isClass) {
			LLVMBuildStore(builder, obj, ptr);
		}
		
		return ptr;
	}
	
	LLVMValueRef visit(IndexExpression e) {
		return LLVMBuildLoad(builder, addressOf(e), "");
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
		
		LLVMValueRef[2] args;
		args[0] = buildDString(location.source.filename);
		args[1] = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), location.line, false);
		
		buildCall(druntimeGen.getArrayBound(), args);
		
		LLVMBuildUnreachable(builder);
		
		// And continue regular program flow.
		LLVMPositionBuilderAtEnd(builder, okBB);
	}
	
	LLVMValueRef visit(SliceExpression e) {
		auto t = e.sliced.type.getCanonical();
		
		LLVMValueRef length, ptr;
		if (t.kind == TypeKind.Slice) {
			auto slice = visit(e.sliced);
			
			length = LLVMBuildExtractValue(builder, slice, 0, ".length");
			ptr = LLVMBuildExtractValue(builder, slice, 1, ".ptr");
		} else if (t.kind == TypeKind.Pointer) {
			ptr = visit(e.sliced);
		} else if (t.kind == TypeKind.Array) {
			length = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), t.size, false);
			
			auto zero = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), 0, false);
			ptr = LLVMBuildInBoundsGEP(builder, addressOf(e.sliced), &zero, 1, "");
		} else {
			assert(0, "Don't know how to slice "/+ ~ e.type.toString(context) +/);
		}
		
		auto first = LLVMBuildZExt(builder, visit(e.first), LLVMInt64TypeInContext(llvmCtx), "");
		auto second = LLVMBuildZExt(builder, visit(e.second), LLVMInt64TypeInContext(llvmCtx), "");
		
		auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.ULE, first, second, "");
		if(length) {
			condition = LLVMBuildAnd(builder, condition, LLVMBuildICmp(builder, LLVMIntPredicate.ULE, second, length, ""), "");
		}
		
		genBoundCheck(e.location, condition);
		
		auto sub = LLVMBuildSub(builder, second, first, "");
		
		ptr = LLVMBuildInBoundsGEP(builder, ptr, &first, 1, "");
		
		auto slice = LLVMGetUndef(pass.visit(e.type));
		
		slice = LLVMBuildInsertValue(builder, slice, sub, 0, "");
		slice = LLVMBuildInsertValue(builder, slice, ptr, 1, "");
		
		return slice;
	}
	
	LLVMValueRef visit(CastExpression e) {
		auto value = visit(e.expr);
		auto type = pass.visit(e.type);
		
		final switch(e.kind) with(CastKind) {
			case Invalid :
				assert(0, "Invalid cast");
			
			case IntToPtr :
				return LLVMBuildIntToPtr(builder, value, type, "");
			
			case PtrToInt :
				return LLVMBuildPtrToInt(builder, value, type, "");
			
			case Down :
				LLVMValueRef[2] args;
				args[0] = LLVMBuildBitCast(builder, value, pass.visit(pass.object.getObject()), "");
				args[1] = getTypeid(e.type);
				
				auto result = buildCall(pass.visit(pass.object.getClassDowncast()), args[]);
				return LLVMBuildBitCast(builder, result, type, "");
			
			case IntToBool :
				return LLVMBuildICmp(builder, LLVMIntPredicate.NE, value, LLVMConstInt(LLVMTypeOf(value), 0, false), "");
			
			case Trunc :
				return LLVMBuildTrunc(builder, value, type, "");
			
			case Pad :
				auto t = e.expr.type.getCanonical();
				while (t.kind == TypeKind.Enum) {
					t = t.denum.type.getCanonical();
				}
				
				auto k = t.builtin;
				assert(canConvertToIntegral(k));
				
				return (isIntegral(k) && isSigned(k))
					? LLVMBuildSExt(builder, value, type, "")
					: LLVMBuildZExt(builder, value, type, "");
			
			case Bit :
				return LLVMBuildBitCast(builder, value, type, "");
			
			case Qual :
			case Exact :
				return value;
		}
	}
	
	auto buildCall(LLVMValueRef callee, LLVMValueRef[] args) {
		// Check if we need to invoke.
		foreach_reverse(ref b; unwindBlocks) {
			if(b.kind == BlockKind.Success) {
				continue;
			}
			
			// We have a failure case.
			auto currentBB = LLVMGetInsertBlock(builder);
			auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
			
			if(!b.landingPadBB) {
				auto landingPadBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "landingPad");
				
				LLVMPositionBuilderAtEnd(builder, landingPadBB);
				
				auto landingPad = LLVMBuildLandingPad(
					builder,
					LLVMStructTypeInContext(llvmCtx, [LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0), LLVMInt32TypeInContext(llvmCtx)].ptr, 2, false),
					pass.visit(pass.object.getPersonality()),
					cast(uint) catchClauses.length,
					"",
				);
				
				if (!lpContext) {
					// Backup current block
					auto backupCurrentBlock = LLVMGetInsertBlock(builder);
					LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(LLVMGetBasicBlockParent(backupCurrentBlock)));
					
					// Create an alloca for this variable.
					lpContext = LLVMBuildAlloca(builder, LLVMTypeOf(landingPad), "lpContext");
					
					LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
				}
				
				// TODO: handle cleanup.
				// For now assume always cleanup.
				// This is inneffiscient, but works.
				LLVMSetCleanup(landingPad, true);
				
				foreach_reverse(c; catchClauses) {
					LLVMAddClause(landingPad, c);
				}
				
				LLVMBuildStore(builder, landingPad, lpContext);
				
				if(!b.unwindBB) {
					b.unwindBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unwind");
				}
				
				LLVMBuildBr(builder, b.unwindBB);
				
				LLVMPositionBuilderAtEnd(builder, currentBB);
				b.landingPadBB = landingPadBB;
			}
			
			auto landingPadBB = b.landingPadBB;
			auto thenBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "then");
			
			auto ret = LLVMBuildInvoke(builder, callee, args.ptr, cast(uint) args.length, thenBB, landingPadBB, "");
			
			LLVMMoveBasicBlockAfter(thenBB, currentBB);
			
			LLVMPositionBuilderAtEnd(builder, thenBB);
			
			return ret;
		}
		
		return LLVMBuildCall(builder, callee, args.ptr, cast(uint) args.length, "");
	}
	
	private LLVMValueRef buildCall(CallExpression c) {
		auto cType = c.callee.type.getCanonical().asFunctionType();
		auto contexts = cType.contexts;
		auto params = cType.parameters;
		
		LLVMValueRef[] args;
		args.length = contexts.length + c.args.length;
		
		auto callee = visit(c.callee);
		foreach (i, ctx; contexts) {
			args[i] = LLVMBuildExtractValue(builder, callee, cast(uint) (i + 1), "");
		}
		
		auto firstarg = contexts.length;
		if (firstarg) {
			callee = LLVMBuildExtractValue(builder, callee, 0, "");
		}
		
		uint i = 0;
		foreach(t; params) {
			args[i + firstarg] = t.isRef
				? addressOf(c.args[i])
				: visit(c.args[i]);
			i++;
		}
		
		// Handle variadic functions.
		while(i < c.args.length) {
			args[i + firstarg] = visit(c.args[i]);
			i++;
		}
		
		return buildCall(callee, args);
	}
	
	LLVMValueRef visit(CallExpression c) {
		return c.callee.type.asFunctionType().returnType.isRef
			? LLVMBuildLoad(builder, buildCall(c), "")
			: buildCall(c);
	}
	
	LLVMValueRef visit(TupleExpression e) {
		auto tuple = LLVMGetUndef(pass.visit(e.type));
		
		uint i = 0;
		foreach(v; e.values.map!(v => visit(v))) {
			tuple = LLVMBuildInsertValue(builder, tuple, v, i++, "");
		}
		
		return tuple;
	}
	
	LLVMValueRef visit(CompileTimeTupleExpression e) {
		auto fields = e.values.map!(v => visit(v)).array();
		auto t = pass.visit(e.type);
		switch(LLVMGetTypeKind(t)) with(LLVMTypeKind) {
			case Struct :
				return LLVMConstNamedStruct(t, fields.ptr, cast(uint) fields.length);
			
			case Array :
				return LLVMConstArray(LLVMGetElementType(t), fields.ptr, cast(uint) fields.length);
			
			default :
				break;
		}
		
		assert(0, "Invalid type tuple.");
	}
	
	LLVMValueRef visit(VoidInitializer v) {
		return LLVMGetUndef(pass.visit(v.type));
	}
	
	LLVMValueRef visit(AssertExpression e) {
		auto test = visit(e.condition);
		
		auto testBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(testBB);
		
		auto failBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "assert_fail");
		auto successBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "assert_success");
		
		auto br = LLVMBuildCondBr(builder, test, successBB, failBB);
		
		// We assume that assert fail is unlikely.
		LLVMSetMetadata(br, profKindID, unlikelyBranch);
		
		// Emit assert call
		LLVMPositionBuilderAtEnd(builder, failBB);
		
		LLVMValueRef[3] args;
		args[1] = buildDString(e.location.source.filename);
		args[2] = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), e.location.line, false);
		
		if(e.message) {
			args[0] = visit(e.message);
			buildCall(druntimeGen.getAssertMessage(), args[]);
		} else {
			buildCall(druntimeGen.getAssert(), args[1 .. $]);
		}
		
		// Conclude that block.
		LLVMBuildUnreachable(builder);
		
		// Now continue regular execution flow.
		LLVMPositionBuilderAtEnd(builder, successBB);
		
		// XXX: should figure out what is the right value to return.
		return null;
	}
	
	LLVMValueRef visit(DynamicTypeidExpression e) {
		auto vtbl = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, visit(e.argument), 0, ""), "");
		return LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, vtbl, 0, ""), "");
	}
	
	private LLVMValueRef getTypeid(Type t) {
		t = t.getCanonical();
		if (t.kind == TypeKind.Class) {
			// Ensure that the thing is generated.
			auto c = t.dclass;
			buildClassType(c);
			
			return getTypeInfo(c);
		}
		
		assert(0, "Not implemented");
	}
	
	LLVMValueRef visit(StaticTypeidExpression e) {
		return getTypeid(e.argument);
	}
	
	LLVMValueRef visit(VtblExpression e) {
		// Vtbl do not have a known type in D, so we need to cast.
		return LLVMBuildPointerCast(builder, pass.getVtbl(e.dclass), pass.visit(e.type), "");
	}
}

struct AddressOfGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) in {
		assert(e.isLvalue, "You can only compute addresses of lvalues.");
	} body {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(VariableExpression e) in {
		assert(e.var.storage != Storage.Enum, "enum have no address.");
	} body {
		return pass.visit(e.var);
	}
	
	LLVMValueRef visit(FieldExpression e) {
		auto base = e.expr;
		
		LLVMValueRef ptr;
		if (base.isLvalue) {
			ptr = visit(base);
		} else {
			auto eg = ExpressionGen(pass);
			ptr = eg.visit(base);
		}
		
		// Pointer auto dereference in D.
		while(1) {
			auto pointed = LLVMGetElementType(LLVMTypeOf(ptr));
			auto kind = LLVMGetTypeKind(pointed);
			if(kind != LLVMTypeKind.Pointer) {
				assert(kind == LLVMTypeKind.Struct);
				break;
			}
			
			ptr = LLVMBuildLoad(builder, ptr, "");
		}
		
		return LLVMBuildStructGEP(builder, ptr, e.field.index, "");
	}
	
	LLVMValueRef visit(ThisExpression e) {
		assert(thisPtr, "no this pointer");
		assert(e.isLvalue, "this is not an lvalue");
		
		return thisPtr;
	}
	
	LLVMValueRef visit(ContextExpression e) in {
		assert(e.type.kind == TypeKind.Context, "ContextExpression must be of ContextType");
	} body {
		return pass.getContext(e.type.context);
	}
	
	LLVMValueRef visit(UnaryExpression e) {
		if(e.op == UnaryOp.Dereference) {
			return ExpressionGen(pass).visit(e.expr);
		}
		
		assert(0, "not an lvalue ??");
	}
	
	LLVMValueRef visit(CastExpression e) {
		auto value = visit(e.expr);
		auto type = pass.visit(e.type);
		
		final switch(e.kind) with(CastKind) {
			case Invalid :
			case IntToPtr :
			case PtrToInt :
			case Down :
			case IntToBool :
			case Trunc :
			case Pad :
				assert(0, "Not an lvalue");
			
			case Bit :
				return LLVMBuildBitCast(builder, value, LLVMPointerType(type, 0), "");
			
			case Qual :
			case Exact :
				return value;
		}
	}
	
	LLVMValueRef visit(CallExpression c) {
		return ExpressionGen(pass).buildCall(c);
	}
	
	LLVMValueRef visit(IndexExpression e) {
		return computeIndexPtr(e.location, e.indexed, e.index);
	}
	
	auto computeIndexPtr(Location location, Expression indexed, Expression index) {
		auto t = indexed.type.getCanonical();
		
		if (t.kind == TypeKind.Slice) {
			auto slice = ExpressionGen(pass).visit(indexed);
			auto i = ExpressionGen(pass).visit(index);
			
			auto length = LLVMBuildExtractValue(builder, slice, 0, ".length");
			
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.ULT, LLVMBuildZExt(builder, i, LLVMInt64TypeInContext(llvmCtx), ""), length, "");
			ExpressionGen(pass).genBoundCheck(location, condition);
			
			auto ptr = LLVMBuildExtractValue(builder, slice, 1, ".ptr");
			return LLVMBuildInBoundsGEP(builder, ptr, &i, 1, "");
		} else if (t.kind == TypeKind.Pointer) {
			auto ptr = ExpressionGen(pass).visit(indexed);
			auto i = ExpressionGen(pass).visit(index);
			return LLVMBuildInBoundsGEP(builder, ptr, &i, 1, "");
		} else if (t.kind == TypeKind.Array) {
			auto ptr = visit(indexed);
			auto i = ExpressionGen(pass).visit(index);
			
			auto condition = LLVMBuildICmp(
				builder,
				LLVMIntPredicate.ULT,
				LLVMBuildZExt(builder, i, LLVMInt64TypeInContext(llvmCtx), ""),
				LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), t.size, false),
				"",
			);
			
			ExpressionGen(pass).genBoundCheck(location, condition);
			
			LLVMValueRef[2] indices;
			indices[0] = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), 0, false);
			indices[1] = i;
			
			return LLVMBuildInBoundsGEP(builder, ptr, indices.ptr, indices.length, "");
		}
		
		assert(0, "Don't know how to index "/+ ~ indexed.type.toString(context) +/);
	}
}

