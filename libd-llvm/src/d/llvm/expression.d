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
		auto t = cast(BuiltinType) peelAlias(e.type).type;
		assert(t);
		
		if(isSigned(t.kind)) {
			return handleBinaryOp!LLVMSignedBuildOp(e);
		} else {
			return handleBinaryOp!LLVMUnsignedBuildOp(e);
		}
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
		auto t = cast(BuiltinType) peelAlias(e.type).type;
		assert(t);
		
		if(isSigned(t.kind)) {
			return handleBinaryOpAssign!LLVMSignedBuildOp(e);
		} else {
			return handleBinaryOpAssign!LLVMUnsignedBuildOp(e);
		}
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
		auto type = peelAlias(e.lhs.type).type;
		if (auto t = cast(BuiltinType) type) {
			if(isSigned(t.kind)) {
				return handleComparaison(e, signedPredicate);
			} else {
				return handleComparaison(e, unsignedPredicate);
			}
		} else if(cast(PointerType) type) {
			return handleComparaison(e, unsignedPredicate);
		}
		
		assert(0, "Don't know how to compare " ~ e.lhs.type.toString(context) ~ " with " ~ e.rhs.type.toString(context));
	}
	
	private auto handleLogicalBinary(bool shortCircuitOnTrue)(BinaryExpression e) {
		auto lhs = visit(e.lhs);
		
		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);
		
		static if(shortCircuitOnTrue) {
			auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "or_short_circuit");
			auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "and_short_circuit");
			auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "and_merge");
			LLVMBuildCondBr(builder, lhs, rhsBB, mergeBB);
		}
		
		// Emit rhs
		LLVMPositionBuilderAtEnd(builder, rhsBB);
		
		auto rhs = visit(e.rhs);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of then can change the current block, so we put everything in order.
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
				auto value = LLVMBuildAdd(builder, LLVMBuildLoad(builder, ptr, ""), LLVMConstInt(pass.visit(e.type), 1, true), "");
				
				LLVMBuildStore(builder, value, ptr);
				return value;
			
			case PreDec :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildSub(builder, LLVMBuildLoad(builder, ptr, ""), LLVMConstInt(pass.visit(e.type), 1, true), "");
				
				LLVMBuildStore(builder, value, ptr);
				return value;
			
			case PostInc :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				
				LLVMBuildStore(builder, LLVMBuildAdd(builder, value, LLVMConstInt(pass.visit(e.type), 1, true), ""), ptr);
				return value;
			
			case PostDec :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				
				LLVMBuildStore(builder, LLVMBuildSub(builder, value, LLVMConstInt(pass.visit(e.type), 1, true), ""), ptr);
				return value;
			
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
	
	LLVMValueRef visit(ThisExpression e) {
		assert(thisPtr, "No this pointer");
		return e.isLvalue ? LLVMBuildLoad(builder, thisPtr, "") : thisPtr;
	}
	
	LLVMValueRef visit(VariableExpression e) {
		import d.ast.base;
		if(e.var.storage == Storage.Enum) {
			return pass.visit(e.var);
		} else {
			return LLVMBuildLoad(builder, addressOf(e), "");
		}
	}
	
	LLVMValueRef visit(FieldExpression e) {
		if(e.isLvalue) {
			return LLVMBuildLoad(builder, addressOf(e), "");
		}
		
		return LLVMBuildExtractValue(builder, visit(e.expr), e.field.index, "");
	}
	
	LLVMValueRef visit(ParameterExpression e) {
		return LLVMBuildLoad(builder, addressOf(e), "");
	}
	
	LLVMValueRef visit(FunctionExpression e) {
		return pass.visit(e.fun);
	}
	
	LLVMValueRef visit(MethodExpression e) {
		auto type = cast(DelegateType) peelAlias(e.type).type;
		assert(type);
		
		auto ctxValue = type.context.isRef
			? addressOf(e.expr)
			: visit(e.expr);
		
		LLVMValueRef fun;
		if(auto m = cast(Method) e.method) {
			auto cd = (cast(ClassType) peelAlias(e.expr.type).type).dclass;
			assert(cd, "Virtual dispatch can only be done on classes.");
			
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
		
		auto dt = peelAlias(e.type).type;
		if(auto pt = cast(PointerType) dt) {
			auto st = cast(StructType) peelAlias(pt.pointed).type;
			auto init = LLVMBuildLoad(builder, getNewInit(st.dstruct), "");
			args = init ~ args;
			
			auto obj = buildCall(ctor, args);
			LLVMBuildStore(builder, obj, ptr);
		} else if(auto ct = cast(ClassType) dt) {
			auto init = LLVMBuildLoad(builder, getNewInit(ct.dclass), "");
			LLVMBuildStore(builder, init, ptr);
			
			auto castedPtr = LLVMBuildBitCast(builder, ptr, LLVMTypeOf(LLVMGetFirstParam(ctor)), "");
			
			args = castedPtr ~ args;
			buildCall(ctor, args);
		} else {
			assert(0, "not implemented");
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
		
		LLVMValueRef args[2];
		args[0] = buildDString(location.source.filename);
		args[1] = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), location.line, false);
		
		buildCall(druntimeGen.getArrayBound(), args);
		
		LLVMBuildUnreachable(builder);
		
		// And continue regular program flow.
		LLVMPositionBuilderAtEnd(builder, okBB);
	}
	
	LLVMValueRef visit(SliceExpression e) {
		assert(e.first.length == 1 && e.second.length == 1);
		auto type = peelAlias(e.sliced.type).type;
		
		LLVMValueRef length, ptr;
		if(typeid(type) is typeid(SliceType)) {
			auto slice = visit(e.sliced);
			
			length = LLVMBuildExtractValue(builder, slice, 0, ".length");
			ptr = LLVMBuildExtractValue(builder, slice, 1, ".ptr");
		} else if(typeid(type) is typeid(PointerType)) {
			ptr = visit(e.sliced);
		} else if(auto asArray = cast(ArrayType) type) {
			length = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), asArray.size, false);
			
			auto zero = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), 0, false);
			ptr = LLVMBuildInBoundsGEP(builder, addressOf(e.sliced), &zero, 1, "");
		} else {
			assert(0, "Don't know how to slice " ~ e.type.toString(context));
		}
		
		auto first = LLVMBuildZExt(builder, visit(e.first[0]), LLVMInt64TypeInContext(llvmCtx), "");
		auto second = LLVMBuildZExt(builder, visit(e.second[0]), LLVMInt64TypeInContext(llvmCtx), "");
		
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
			
			case Down :
				LLVMValueRef[2] args;
				args[0] = LLVMBuildBitCast(builder, value, pass.visit(pass.object.getObject()), "");
				args[1] = getTypeid(e.type);
				
				auto result = buildCall(pass.visit(pass.object.getClassDowncast()), args[]);
				return LLVMBuildBitCast(builder, result, type, "");
			
			case IntegralToBool :
				return LLVMBuildICmp(builder, LLVMIntPredicate.NE, value, LLVMConstInt(LLVMTypeOf(value), 0, false), "");
			
			case Trunc :
				return LLVMBuildTrunc(builder, value, type, "");
			
			case Pad :
				auto bt = cast(BuiltinType) peelAlias(e.expr.type).type;
				assert(bt);
				
				auto k = bt.kind;
				if(isChar(k)) {
					k = integralOfChar(k);
				}
				
				assert(k == TypeKind.Bool || isIntegral(k));
				if(k == TypeKind.Bool || !isSigned(k)) {
					return LLVMBuildZExt(builder, value, type, "");
				} else {
					return LLVMBuildSExt(builder, value, type, "");
				}
			
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
	
	LLVMValueRef visit(CallExpression c) {
		auto callee = visit(c.callee);
		
		ParamType[] paramTypes;
		LLVMValueRef[] args;
		uint firstarg = 0;
		auto calleeType = peelAlias(c.callee.type).type;
		if(auto type = cast(DelegateType) calleeType) {
			paramTypes = type.paramTypes;
			
			auto fun = LLVMBuildExtractValue(builder, callee, 0, "");
			
			firstarg++;
			args.length = c.args.length + 1;
			args[0] = LLVMBuildExtractValue(builder, callee, 1, "");
			
			callee = fun;
		} else if(auto type = cast(FunctionType) calleeType) {
			paramTypes = type.paramTypes;
			args.length = c.args.length;
		} else {
			assert(0, "You can only call function and delegates !");
		}
		
		uint i = 0;
		foreach(t; paramTypes) {
			if(t.isRef) {
				args[i + firstarg] = addressOf(c.args[i]);
			} else {
				args[i + firstarg] = visit(c.args[i]);
			}
			
			i++;
		}
		
		// Handle variadic functions.
		while(i < c.args.length) {
			args[i + firstarg] = visit(c.args[i]);
			i++;
		}
		
		return buildCall(callee, args);
	}
	
	private auto handleTuple(bool isCT)(TupleExpressionImpl!isCT e) {
		auto fields = e.values.map!(v => visit(v)).array();
		
		// Hack around the difference between struct and named struct in LLVM.
		return LLVMConstNamedStruct(pass.visit(e.type), fields.ptr, cast(uint) fields.length);
	}
	
	LLVMValueRef visit(TupleExpression e) {
		return handleTuple(e);
	}
	
	LLVMValueRef visit(CompileTimeTupleExpression e) {
		return handleTuple(e);
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
		
		LLVMValueRef args[3];
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
	
	private auto getTypeid(QualType t) {
		if(auto ct = cast(ClassType) peelAlias(t).type) {
			// Ensure that the thing is generated.
			auto c = ct.dclass; 
			buildClassType(c);
			
			return getTypeInfo(c);
		}
		
		assert(0, "Not implemented");
	}
	
	LLVMValueRef visit(StaticTypeidExpression e) {
		return getTypeid(e.argument);
	}
}

struct AddressOfGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(VariableExpression e) {
		import d.ast.base;
		assert(e.var.storage != Storage.Enum, "enum have no address.");
		
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
	
	LLVMValueRef visit(ParameterExpression e) {
		return pass.visit(e.param);
	}
	
	LLVMValueRef visit(ThisExpression e) {
		assert(thisPtr, "no this pointer");
		assert(e.isLvalue, "this is not an lvalue");
		
		return thisPtr;
	}
	
	LLVMValueRef visit(ContextExpression e) {
		auto type = pass.visit(e.type);
		auto value = contexts[$ - 1].context;
		foreach_reverse(i, c; contexts) {
			value = LLVMBuildPointerCast(builder, value, LLVMTypeOf(c.context), "");
			
			if (c.type is type) {
				return LLVMBuildPointerCast(builder, value, LLVMPointerType(type, 0), "");
			}
			
			value = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, value, 0, ""), "");
		}
		
		assert(0, "No context available.");
	}
	
	LLVMValueRef visit(UnaryExpression e) {
		if(e.op == UnaryOp.Dereference) {
			auto eg = ExpressionGen(pass);
			return eg.visit(e.expr);
		}
		
		assert(0, "not an lvalue ??");
	}
	
	LLVMValueRef visit(CastExpression e) {
		auto value = visit(e.expr);
		auto type = pass.visit(e.type);
		
		final switch(e.kind) with(CastKind) {
			case Invalid :
			case Down :
			case IntegralToBool :
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
	
	LLVMValueRef visit(IndexExpression e) {
		assert(e.arguments.length == 1);
		
		return computeIndexPtr(e.location, e.indexed, e.arguments[0]);
	}
	
	auto computeIndexPtr(Location location, Expression indexed, Expression index) {
		auto eg = ExpressionGen(pass);
		auto type = peelAlias(indexed.type).type;
		
		if(typeid(type) is typeid(SliceType)) {
			auto slice = eg.visit(indexed);
			auto i = eg.visit(index);
			
			auto length = LLVMBuildExtractValue(builder, slice, 0, ".length");
			
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.ULT, LLVMBuildZExt(builder, i, LLVMInt64TypeInContext(llvmCtx), ""), length, "");
			eg.genBoundCheck(location, condition);
			
			auto ptr = LLVMBuildExtractValue(builder, slice, 1, ".ptr");
			return LLVMBuildInBoundsGEP(builder, ptr, &i, 1, "");
		} else if(typeid(type) is typeid(PointerType)) {
			auto ptr = eg.visit(indexed);
			auto i = eg.visit(index);
			return LLVMBuildInBoundsGEP(builder, ptr, &i, 1, "");
		} else if(auto asArray = cast(ArrayType) type) {
			auto ptr = visit(indexed);
			auto i = eg.visit(index);
			
			auto condition = LLVMBuildICmp(
				builder,
				LLVMIntPredicate.ULT,
				LLVMBuildZExt(builder, i, LLVMInt64TypeInContext(llvmCtx), ""),
				LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), asArray.size, false),
				"",
			);
			
			eg.genBoundCheck(location, condition);
			
			LLVMValueRef indices[2];
			indices[0] = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), 0, false);
			indices[1] = i;
			
			return LLVMBuildInBoundsGEP(builder, ptr, indices.ptr, indices.length, "");
		}
		
		assert(0, "Don't know how to index " ~ indexed.type.toString(context));
	}
}

