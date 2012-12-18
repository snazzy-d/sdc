module d.backend.expression;

import d.backend.codegen;

import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import util.visitor;

import sdc.location;

import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

final class ExpressionGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			auto msg = typeid(e).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(e.location, msg);
			
			assert(0, msg);
		})(e);
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
	
	LLVMValueRef visit(CommaExpression ce) {
		visit(ce.lhs);
		
		return visit(ce.rhs);
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMBuildLoad(builder, addressOf(e), "");
	}
	
	LLVMValueRef visit(AssignExpression e) {
		auto ptr = addressOf(e.lhs);
		auto value = visit(e.rhs);
		
		LLVMBuildStore(builder, value, ptr);
		
		return value;
	}
	
	LLVMValueRef visit(AddressOfExpression e) {
		return addressOf(e.expression);
	}
	
	LLVMValueRef visit(DereferenceExpression e) {
		return LLVMBuildLoad(builder, visit(e.expression), "");
	}
	
	private auto handleIncrement(bool pre, IncrementExpression)(IncrementExpression e, int step) {
		auto ptr = addressOf(e.expression);
		
		auto preValue = LLVMBuildLoad(builder, ptr, "");
		auto type = e.expression.type;
		
		LLVMValueRef postValue;
		
		if(auto ptrType = cast(PointerType) type) {
			auto indice = LLVMConstInt(LLVMInt64TypeInContext(context), step, true);
			postValue = LLVMBuildInBoundsGEP(builder, preValue, &indice, 1, "");
		} else {
			postValue = LLVMBuildAdd(builder, preValue, LLVMConstInt(pass.visit(type), step, true), "");
		}
		
		LLVMBuildStore(builder, postValue, ptr);
		
		// PreIncrement return the value after it is incremented.
		static if(pre) {
			return postValue;
		} else {
			return preValue;
		}
	}
	
	LLVMValueRef visit(PreIncrementExpression e) {
		return handleIncrement!true(e, 1);
	}
	
	LLVMValueRef visit(PreDecrementExpression e) {
		return handleIncrement!true(e, -1);
	}
	
	LLVMValueRef visit(PostIncrementExpression e) {
		return handleIncrement!false(e, 1);
	}
	
	LLVMValueRef visit(PostDecrementExpression e) {
		return handleIncrement!false(e, -1);
	}
	
	LLVMValueRef visit(UnaryMinusExpression e) {
		return LLVMBuildSub(builder, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expression), "");
	}
	
	LLVMValueRef visit(NotExpression e) {
		// Is it the right way ?
		return LLVMBuildICmp(builder, LLVMIntPredicate.EQ, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expression), "");
	}
	
	private auto handleBinaryOp(alias LLVMBuildOp, BinaryExpression)(BinaryExpression e) {
		// XXX: should be useless, but order of evaluation of parameters is bugguy.
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		
		return LLVMBuildOp(builder, lhs, rhs, "");
	}
	
	private auto handleBinaryOpAssign(alias LLVMBuildOp, BinaryExpression)(BinaryExpression e) {
		auto lhsPtr = addressOf(e.lhs);
		
		auto lhs = LLVMBuildLoad(builder, lhsPtr, "");
		auto rhs = visit(e.rhs);
		
		auto value = LLVMBuildOp(builder, lhs, rhs, "");
		
		LLVMBuildStore(builder, value, lhsPtr);
		
		return value;
	}
	
	private auto handleBinaryOp(alias LLVMSignedBuildOp, alias LLVMUnsignedBuildOp, BinaryExpression)(BinaryExpression e) {
		pass.visit(e.type);
		
		if(isSigned) {
			return handleBinaryOp!LLVMSignedBuildOp(e);
		} else {
			return handleBinaryOp!LLVMUnsignedBuildOp(e);
		}
	}
	
	LLVMValueRef visit(AddExpression add) {
		return handleBinaryOp!LLVMBuildAdd(add);
	}
	
	LLVMValueRef visit(SubExpression sub) {
		return handleBinaryOp!LLVMBuildSub(sub);
	}
	
	LLVMValueRef visit(AddAssignExpression add) {
		return handleBinaryOpAssign!LLVMBuildAdd(add);
	}
	
	LLVMValueRef visit(SubAssignExpression sub) {
		return handleBinaryOpAssign!LLVMBuildSub(sub);
	}
	
	LLVMValueRef visit(MulExpression mul) {
		return handleBinaryOp!LLVMBuildMul(mul);
	}
	
	LLVMValueRef visit(DivExpression div) {
		return handleBinaryOp!(LLVMBuildSDiv, LLVMBuildUDiv)(div);
	}
	
	LLVMValueRef visit(ModExpression mod) {
		return handleBinaryOp!(LLVMBuildSRem, LLVMBuildURem)(mod);
	}
	
	private auto handleLogicalBinary(string operation)(BinaryExpression!operation e) if(operation == "&&" || operation == "||") {
		auto lhs = visit(e.lhs);
		
		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);
		
		static if(operation == "&&") {
			auto rhsBB = LLVMAppendBasicBlock(fun, "and_short_circuit");
			auto mergeBB = LLVMAppendBasicBlock(fun, "and_merge");
			LLVMBuildCondBr(builder, lhs, rhsBB, mergeBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlock(fun, "or_short_circuit");
			auto mergeBB = LLVMAppendBasicBlock(fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		}
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, rhsBB);
		
		auto rhs = visit(e.rhs);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of then can change the current block, so we put everything in order.
		rhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, rhsBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		
		//Generate phi to get the result.
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
	
	LLVMValueRef visit(LogicalAndExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(LogicalOrExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		if(e.symbol.isEnum) {
			return pass.visit(e.symbol);
		} else {
			return LLVMBuildLoad(builder, addressOf(e), "");
		}
	}
	
	LLVMValueRef visit(FieldExpression e) {
		// FIXME: handle rvalues with LLVMBuildExtractValue.
		try {
			return LLVMBuildLoad(builder, addressOf(e), "");
		} catch(Exception exp) {
			import std.stdio;
			writeln("FieldExpression isn't an lvalue.");
			
			return LLVMBuildExtractValue(builder, visit(e.expression), e.field.index, "");
		}
	}
	
	LLVMValueRef visit(IndexExpression e) {
		return LLVMBuildLoad(builder, addressOf(e), "");
	}
	
	LLVMValueRef visit(SliceExpression e) {
		assert(e.first.length == 1 && e.second.length == 1);
		
		auto indexed = addressOf(e.indexed);
		auto first = LLVMBuildZExt(builder, visit(e.first[0]), LLVMInt64TypeInContext(context), "");
		auto second = LLVMBuildZExt(builder, visit(e.second[0]), LLVMInt64TypeInContext(context), "");
		
		// To ensure bound check. Before ptr calculation for optimization purpose.
		computeIndice(e.location, e.indexed.type, indexed, second);
		
		auto length = LLVMBuildSub(builder, second, first, "");
		auto ptr = computeIndice(e.location, e.indexed.type, indexed, first);
		
		auto slice = LLVMGetUndef(pass.visit(e.type));
		
		slice = LLVMBuildInsertValue(builder, slice, length, 0, "");
		slice = LLVMBuildInsertValue(builder, slice, ptr, 1, "");
		
		return slice;
	}
	
	private auto handleComparaison(LLVMIntPredicate predicate, BinaryExpression)(BinaryExpression e) {
		return handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, predicate, lhs, rhs, name);
		})(e);
	}
	
	private auto handleComparaison(LLVMIntPredicate signedPredicate, LLVMIntPredicate unsignedPredicate, BinaryExpression)(BinaryExpression e) {
		// TODO: implement type comparaison.
		// assert(e.lhs.type == e.rhs.type);
		
		pass.visit(e.lhs.type);
		
		if(isSigned) {
			return handleComparaison!signedPredicate(e);
		} else {
			return handleComparaison!unsignedPredicate(e);
		}
	}
	
	LLVMValueRef visit(EqualityExpression e) {
		return handleComparaison!(LLVMIntPredicate.EQ)(e);
	}
	
	LLVMValueRef visit(NotEqualityExpression e) {
		return handleComparaison!(LLVMIntPredicate.NE)(e);
	}
	
	LLVMValueRef visit(LessExpression e) {
		return handleComparaison!(LLVMIntPredicate.SLT, LLVMIntPredicate.ULT)(e);
	}
	
	LLVMValueRef visit(LessEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.SLE, LLVMIntPredicate.ULE)(e);
	}
	
	LLVMValueRef visit(GreaterExpression e) {
		return handleComparaison!(LLVMIntPredicate.SGT, LLVMIntPredicate.UGT)(e);
	}
	
	LLVMValueRef visit(GreaterEqualExpression e) {
		return handleComparaison!(LLVMIntPredicate.SGE, LLVMIntPredicate.UGE)(e);
	}
	
	LLVMValueRef visit(PadExpression e) {
		auto type = pass.visit(e.type);
		
		pass.visit(e.expression.type);
		if(isSigned) {
			return LLVMBuildSExt(builder, visit(e.expression), type, "");
		} else {
			return LLVMBuildZExt(builder, visit(e.expression), type, "");
		}
	}
	
	LLVMValueRef visit(TruncateExpression e) {
		return LLVMBuildTrunc(builder, visit(e.expression), pass.visit(e.type), "");
	}
	
	LLVMValueRef visit(BitCastExpression e) {
		return LLVMBuildBitCast(builder, visit(e.expression), pass.visit(e.type), "");
	}
	
	LLVMValueRef visit(CallExpression c) {
		auto callee = visit(c.callee);
		
		LLVMValueRef[] arguments;
		arguments.length = c.arguments.length;
		
		auto type = cast(FunctionType) c.callee.type;
		uint i;
		foreach(param; type.parameters) {
			if(param.isReference) {
				arguments[i] = addressOf(c.arguments[i]);
			} else {
				arguments[i] = visit(c.arguments[i]);
			}
			
			i++;
		}
		
		// Handle variadic functions.
		while(i < arguments.length) {
			arguments[i] = visit(c.arguments[i]);
			i++;
		}
		
		return LLVMBuildCall(builder, callee, arguments.ptr, cast(uint) arguments.length, "");
	}
	
	LLVMValueRef visit(TupleExpression e) {
		auto fields = e.values.map!(v => visit(v)).array();
		
		// Hack around the difference between struct and named struct in LLVM.
		if(e.type) {
			auto type = pass.visit(e.type);
			return LLVMConstNamedStruct(type, fields.ptr, cast(uint) fields.length);
		}
		
		return LLVMConstStructInContext(context, fields.ptr, cast(uint) fields.length, false);
	}
	
	LLVMValueRef visit(VoidInitializer v) {
		return LLVMGetUndef(pass.visit(v.type));
	}
	
	LLVMValueRef visit(AssertExpression e) {
		auto test = visit(e.arguments[0]);
		
		auto testBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(testBB);
		
		auto failBB = LLVMAppendBasicBlock(fun, "assert_fail");
		auto successBB = LLVMAppendBasicBlock(fun, "assert_success");
		
		LLVMBuildCondBr(builder, test, successBB, failBB);
		
		// Emit assert call
		LLVMPositionBuilderAtEnd(builder, failBB);
		
		auto args = [buildDString(e.location.filename), LLVMConstInt(LLVMInt32TypeInContext(context), e.location.line, false)];
		LLVMBuildCall(builder, druntimeGen.getAssert(), args.ptr, 2, "");
		
		// Conclude that block.
		LLVMBuildUnreachable(builder);
		
		// Now continue regular execution flow.
		LLVMPositionBuilderAtEnd(builder, successBB);
		
		// XXX: should figure out what is the right value to return.
		return null;
	}
}

final class AddressOfGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		assert(!e.symbol.isEnum, "enum have no address.");
		
		return pass.visit(e.symbol);
	}
	
	LLVMValueRef visit(FieldExpression e) {
		auto ptr = visit(e.expression);
		
		return LLVMBuildStructGEP(builder, ptr, e.field.index, "");
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMGetFirstParam(LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder)));
	}
	
	LLVMValueRef visit(DereferenceExpression e) {
		return pass.visit(e.expression);
	}
	
	LLVMValueRef visit(BitCastExpression e) {
		return LLVMBuildBitCast(builder, visit(e.expression), LLVMPointerType(pass.visit(e.type), 0), "");
	}
	
	LLVMValueRef computeIndice(Location location, Type indexedType, LLVMValueRef indexed, LLVMValueRef indice) {
		if(typeid(indexedType) is typeid(SliceType)) {
			auto length = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, indexed, 0, ""), ".length");
			
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.ULT, LLVMBuildZExt(builder, indice, LLVMInt64TypeInContext(context), ""), length, ".boundCheck");
			auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
			
			auto failBB = LLVMAppendBasicBlock(fun, "arrayBoundFail");
			auto okBB = LLVMAppendBasicBlock(fun, "arrayBoundOK");
			
			LLVMBuildCondBr(builder, condition, okBB, failBB);
			
			// Emit bound check fail code.
			LLVMPositionBuilderAtEnd(builder, failBB);
			
			auto args = [buildDString(location.filename), LLVMConstInt(LLVMInt32TypeInContext(context), location.line, false)];
			LLVMBuildCall(builder, druntimeGen.getArrayBound(), args.ptr, 2, "");
			
			LLVMBuildUnreachable(builder);
			
			// And continue regular program flow.
			LLVMPositionBuilderAtEnd(builder, okBB);
			
			indexed = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, indexed, 1, ""), ".ptr");
		} else if(typeid(indexedType) is typeid(PointerType)) {
			indexed = LLVMBuildLoad(builder, indexed, "");
		} else if(typeid(indexedType) is typeid(StaticArrayType)) {
			auto indices = [LLVMConstInt(LLVMInt64TypeInContext(context), 0, false), indice];
			
			return LLVMBuildInBoundsGEP(builder, indexed, indices.ptr, 2, "");
		} else {
			assert(0, "Don't know how to index this.");
		}
		
		return LLVMBuildInBoundsGEP(builder, indexed, &indice, 1, "");
	}
	
	LLVMValueRef visit(IndexExpression e) {
		assert(e.arguments.length == 1);
		
		auto indexed = visit(e.indexed);
		auto indice = pass.visit(e.arguments[0]);
		
		return computeIndice(e.location, e.indexed.type, indexed, indice);
	}
}

