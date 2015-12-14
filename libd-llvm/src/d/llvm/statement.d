module d.llvm.statement;

import d.llvm.local;

import d.context.location;

import d.ir.expression;
import d.ir.statement;

import util.visitor;

import llvm.c.core;

struct StatementGen {
	private LocalPass pass;
	alias pass this;
	
	LLVMValueRef switchInstr;
	
	struct LabelBlock {
		size_t unwind;
		LLVMBasicBlockRef basic;
	}
	
	LabelBlock continueBlock;
	LabelBlock breakBlock;
	LabelBlock defaultBlock;
	
	import d.context.name;
	LabelBlock[Name] labels;
	
	// Forward goto can only be resolved when the label is reached.
	struct GotoBlock {
		LocalPass.Block[] unwind;
		LLVMBasicBlockRef basic;
	}
	
	GotoBlock[][Name] inFlightGotos;
	
	this(LocalPass pass) {
		this.pass = pass;
	}
	
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(VariableStatement s) {
		define(s.var);
	}
	
	void visit(FunctionStatement s) {
		define(s.fun);
	}
	
	void visit(AggregateStatement s) {
		define(s.aggregate);
	}
	
	private auto genExpression(Expression e) {
		import d.llvm.expression;
		return ExpressionGen(pass).visit(e);
	}
	
	private auto genConstant(CompileTimeExpression e) {
		import d.llvm.constant;
		return ConstantGen(pass.pass).visit(e);
	}
	
	private auto genCall(LLVMValueRef callee, LLVMValueRef[] args) {
		import d.llvm.expression;
		return ExpressionGen(pass).buildCall(callee, args);
	}
	
	void visit(ExpressionStatement e) {
		genExpression(e.expression);
	}
	
	void visit(BlockStatement b) {
		auto oldUnwindBlocks = unwindBlocks;
		foreach(s; b.statements) {
			visit(s);
		}
		
		unwindTo(oldUnwindBlocks.length);
	}
	
	private void maybeBranchTo(LLVMBasicBlockRef destBB) {
		if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			LLVMBuildBr(builder, destBB);
		}
	}
	
	void visit(IfStatement ifs) {
		auto condition = genExpression(ifs.condition);
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto thenBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "then");
		auto elseBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "else");
		auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "merge");
		
		LLVMBuildCondBr(builder, condition, thenBB, elseBB);
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, thenBB);
		
		visit(ifs.then);
		
		// Codegen of then can change the current block, so we put everything in order.
		thenBB = LLVMGetInsertBlock(builder);
		maybeBranchTo(mergeBB);
		
		// Put the else block after the generated stuff.
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		// Emit else
		if (ifs.elseStatement) {
			visit(ifs.elseStatement);
		}
		
		// Codegen of else can change the current block,
		// so we put everything in order.
		elseBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, elseBB);
		
		maybeBranchTo(mergeBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
	}
	
	void visit(LoopStatement l) {
		// Generate initialization if appropriate
		auto oldBreakBlock = breakBlock;
		auto oldContinueBlock = continueBlock;
		scope(exit) {
			breakBlock = oldBreakBlock;
			continueBlock = oldContinueBlock;
		}
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto testBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "loop.test");
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "loop.body");
		auto incBB  = LLVMAppendBasicBlockInContext(llvmCtx, fun, "loop.inc");
		auto exitBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "loop.exit");
		
		breakBlock = LabelBlock(unwindBlocks.length, exitBB);
		continueBlock = LabelBlock(unwindBlocks.length, incBB);
		
		// Jump into the loop.
		maybeBranchTo(l.skipFirstCond ? bodyBB : testBB);
		LLVMPositionBuilderAtEnd(builder, testBB);
		
		// Test and do or jump to done.
		auto condition = genExpression(l.condition);
		LLVMBuildCondBr(builder, condition, bodyBB, exitBB);
		
		// Emit loop body
		auto currentBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(bodyBB, currentBB);
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		visit(l.fbody);
		
		// Codegen of then can change the current block,
		// so we put everything in order.
		currentBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(incBB, currentBB);
		
		maybeBranchTo(incBB);
		
		// Build continue block or alias it to the test.
		LLVMPositionBuilderAtEnd(builder, incBB);
		if (l.increment !is null) {
			genExpression(l.increment);
		}
		
		currentBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(exitBB, currentBB);
		maybeBranchTo(testBB);
		
		LLVMPositionBuilderAtEnd(builder, exitBB);
	}
	
	void visit(ReturnStatement r) {
		LLVMValueRef ret;
		if (r.value) {
			ret = genExpression(r.value);
		}
		
		closeBlockTo(0);
		
		if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			return;
		}
		
		if (r.value) {
			LLVMBuildRet(builder, ret);
		} else {
			LLVMBuildRetVoid(builder);
		}
	}
	
	private void unwindAndBranch(LabelBlock b) in {
		assert(b.basic !is null);
	} body {
		closeBlockTo(b.unwind);
		maybeBranchTo(b.basic);
	}
	
	void visit(BreakStatement s) {
		unwindAndBranch(breakBlock);
	}
	
	void visit(ContinueStatement s) {
		unwindAndBranch(continueBlock);
	}
	
	void visit(SwitchStatement s) {
		auto oldBreakBlock = breakBlock;
		auto oldDefaultBlock = defaultBlock;
		auto oldSwitchInstr = switchInstr;
		
		scope(exit) {
			breakBlock = oldBreakBlock;
			defaultBlock = oldDefaultBlock;
			switchInstr = oldSwitchInstr;
		}
		
		auto unwindBlock = unwindBlocks.length;
		
		auto expression = genExpression(s.expression);
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto defaultBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "default");
		defaultBlock = LabelBlock(unwindBlock, defaultBB);
		
		auto startBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "switchstart");
		
		auto breakBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "switchend");
		breakBlock = LabelBlock(unwindBlock, breakBB);
		
		switchInstr = LLVMBuildSwitch(builder, expression, defaultBB, 0);
		
		LLVMPositionBuilderAtEnd(builder, startBB);
		
		visit(s.statement);
		
		// Codegen of switch body can change the current block, so we put everything in order.
		auto finalBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(breakBB, finalBB);
		
		maybeBranchTo(breakBB);
		
		// Conclude default block if it isn't already.
		if (!LLVMGetBasicBlockTerminator(defaultBB)) {
			LLVMPositionBuilderAtEnd(builder, defaultBB);
			LLVMBuildUnreachable(builder);
		}
		
		LLVMPositionBuilderAtEnd(builder, breakBB);
	}
	
	private void fixupGoto(Name label, LabelBlock block) {
		if (auto ifgsPtr = label in inFlightGotos) {
			auto ifgs = *ifgsPtr;
			inFlightGotos.remove(label);
			
			foreach(ifg; ifgs) {
				auto oldUnwindBlocks = unwindBlocks;
				scope(exit) unwindBlocks = oldUnwindBlocks;
				
				unwindBlocks = ifg.unwind;
				
				LLVMPositionBuilderAtEnd(builder, ifg.basic);
				unwindAndBranch(block);
			}
		}
	}
	
	void visit(CaseStatement s) {
		assert(switchInstr);
		
		auto currentBB = LLVMGetInsertBlock(builder);
		
		auto fun = LLVMGetBasicBlockParent(currentBB);
		auto caseBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "case");
		
		// In fligt goto case will end up here.
		fixupGoto(BuiltinName!"case", LabelBlock(defaultBlock.unwind, caseBB));
		
		LLVMMoveBasicBlockAfter(caseBB, currentBB);
		
		// Conclude that block if it isn't already.
		if (!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMPositionBuilderAtEnd(builder, currentBB);
			LLVMBuildBr(builder, caseBB);
		}
		
		foreach(e; s.cases) {
			LLVMAddCase(switchInstr, genConstant(e), caseBB);
		}
		
		LLVMPositionBuilderAtEnd(builder, caseBB);
	}
	
	void visit(LabeledStatement s) {
		auto currentBB = LLVMGetInsertBlock(builder);
		auto label = s.label;
		
		LLVMBasicBlockRef labelBB;
		
		// default is a magic label.
		if (label == BuiltinName!"default") {
			labelBB = defaultBlock.basic;
		} else {
			import std.string;
			auto fun = LLVMGetBasicBlockParent(currentBB);
			labelBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, label.toStringz(context));
			
			auto block = labels[label] = LabelBlock(unwindBlocks.length, labelBB);
			fixupGoto(label, block);
		}
		
		assert(labelBB !is null);
		LLVMMoveBasicBlockAfter(labelBB, currentBB);
		
		// Conclude that block if it isn't already.
		if (!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMPositionBuilderAtEnd(builder, currentBB);
			LLVMBuildBr(builder, labelBB);
		}
		
		LLVMPositionBuilderAtEnd(builder, labelBB);
		visit(s.statement);
	}
	
	void visit(GotoStatement s) {
		auto label = s.label;
		
		// default is a magic label.
		if (label == BuiltinName!"default") {
			unwindAndBranch(defaultBlock);
			return;
		}
		
		if (auto bPtr = label in labels) {
			unwindAndBranch(*bPtr);
			return;
		}
		
		// Forward goto need to be registered and fixed when we encounter the label.
		if (auto bPtr = label in inFlightGotos) {
			auto b = *bPtr;
			b ~= GotoBlock(unwindBlocks, LLVMGetInsertBlock(builder));
			inFlightGotos[label] = b;
		} else {
			inFlightGotos[label] = [GotoBlock(unwindBlocks, LLVMGetInsertBlock(builder))];
		}
		
		// Should be unreachable, but most of the code expect a BB to be active.
		auto currentBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(currentBB);
		auto postGotoBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unreachable_post_goto");
		LLVMMoveBasicBlockAfter(postGotoBB, currentBB);
		LLVMPositionBuilderAtEnd(builder, postGotoBB);
	}
	
	void visit(ScopeStatement s) {
		assert(s.kind == ScopeKind.Exit, "Only scope exit is supported");
		unwindBlocks ~= Block(BlockKind.Exit, s.statement, null, null);
	}
	
	void visit(AssertStatement s) {
		auto test = genExpression(s.condition);
		
		auto testBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(testBB);
		
		auto failBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "assert_fail");
		auto successBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "assert_success");
		
		auto br = LLVMBuildCondBr(builder, test, successBB, failBB);
		
		// We assume that assert fail is unlikely.
		LLVMSetMetadata(br, profKindID, unlikelyBranch);
		
		// Emit assert call
		LLVMPositionBuilderAtEnd(builder, failBB);
		genHalt(s.location, s.message);
		
		// Now continue regular execution flow.
		LLVMPositionBuilderAtEnd(builder, successBB);
	}
	
	void visit(HaltStatement s) {
		genHalt(s.location, s.message);
	}
	
	void genHalt(Location location, Expression msg) {
		auto floc = location.getFullLocation(context);
		
		LLVMValueRef[3] args;
		args[1] = buildDString(floc.getSource().getFileName().toString());
		args[2] = LLVMConstInt(
			LLVMInt32TypeInContext(llvmCtx),
			floc.getStartLineNumber(),
			false,
		);
		
		if (msg) {
			args[0] = genExpression(msg);
			
			import d.llvm.runtime;
			genCall(RuntimeGen(pass.pass).getAssertMessage(), args[]);
		} else {
			import d.llvm.runtime;
			genCall(RuntimeGen(pass.pass).getAssert(), args[1 .. $]);
		}
		
		// Conclude that block.
		LLVMBuildUnreachable(builder);
	}
	
	void visit(ThrowStatement s) {
		auto value = LLVMBuildBitCast(
			builder,
			genExpression(s.value),
			define(pass.object.getThrowable()),
			"",
		);
		
		genCall(declare(pass.object.getThrow()), [value]);
		LLVMBuildUnreachable(builder);
	}
	
	void visit(TryStatement s) {
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		auto resumeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "resume");
		
		auto oldCatchClauses = catchClauses;
		scope(success) {
			catchClauses = oldCatchClauses;
		}
		
		auto catches = s.catches;
		foreach_reverse(c; catches) {
			auto type = c.type;
			
			import d.llvm.type;
			TypeGen(pass.pass).visit(type);
			catchClauses ~= TypeGen(pass.pass).getTypeInfo(type);
			
			unwindBlocks ~= Block(BlockKind.Catch, c.statement, null, null);
		}
		
		visit(s.statement);
		
		auto currentBB = LLVMGetInsertBlock(builder);
		maybeBranchTo(resumeBB);
		
		auto lastBlock = unwindBlocks[$ - 1];
		unwindBlocks = unwindBlocks[0 .. $ - catches.length];
		
		scope(success) {
			LLVMPositionBuilderAtEnd(builder, resumeBB);
		}
		
		// If no unwind in the first block, we can skip the whole stuff.
		auto unwindBB = lastBlock.unwindBB;
		if (!unwindBB) {
			LLVMMoveBasicBlockAfter(resumeBB, currentBB);
			return;
		}
		
		// Only the first one can have a landingPad.
		auto landingPadBB = lastBlock.landingPadBB;
		if (landingPadBB) {
			LLVMMoveBasicBlockAfter(landingPadBB, currentBB);
			currentBB = landingPadBB;
		}
		
		LLVMPositionBuilderAtEnd(builder, unwindBB);
		auto landingPad = LLVMBuildLoad(builder, lpContext, "");
		auto cid = LLVMBuildExtractValue(builder, landingPad, 1, "");
		
		foreach(c; catches) {
			LLVMMoveBasicBlockAfter(unwindBB, currentBB);
			
			auto catchBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "catch");
			auto nextUnwindBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unwind");
			
			import d.llvm.type;
			auto typeinfo = LLVMBuildBitCast(
				builder,
				TypeGen(pass.pass).getTypeInfo(c.type),
				LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0),
				"",
			);
			
			import d.llvm.runtime;
			auto tid = genCall(RuntimeGen(pass.pass).getEhTypeidFor(), [typeinfo]);
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.EQ, tid, cid, "");
			LLVMBuildCondBr(builder, condition, catchBB, nextUnwindBB);
			
			LLVMMoveBasicBlockAfter(catchBB, unwindBB);
			LLVMPositionBuilderAtEnd(builder, catchBB);
			
			visit(c.statement);
			
			currentBB = LLVMGetInsertBlock(builder);
			maybeBranchTo(resumeBB);
			
			unwindBB = nextUnwindBB;
			LLVMPositionBuilderAtEnd(builder, unwindBB);
		}
		
		LLVMMoveBasicBlockAfter(resumeBB, unwindBB);
		concludeUnwind(fun, unwindBB);
	}
	
	void closeBlockTo(size_t level) {
		auto oldUnwindBlocks = unwindBlocks;
		scope(exit) unwindBlocks = oldUnwindBlocks;
		
		while(unwindBlocks.length > level) {
			import std.array;
			auto b = unwindBlocks.back;
			unwindBlocks.popBack();
			
			if (b.kind == BlockKind.Exit || b.kind == BlockKind.Success) {
				if (LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
					break;
				}
				
				auto oldLocals = pass.locals.dup;
				scope(exit) {
					if (pass.locals.length != oldLocals.length) {
						pass.locals = oldLocals;
					}
				}
				
				visit(b.statement);
			}
		}
	}
	
	void concludeUnwind(LLVMValueRef fun, LLVMBasicBlockRef currentBB) {
		if (LLVMGetBasicBlockTerminator(currentBB)) {
			return;
		}
		
		LLVMPositionBuilderAtEnd(builder, currentBB);
		foreach_reverse(b; unwindBlocks) {
			if (b.kind == BlockKind.Success) {
				continue;
			}
			
			if (!b.unwindBB) {
				b.unwindBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unwind");
			}
			
			LLVMBuildBr(builder, b.unwindBB);
			break;
		}
		
		if (!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMBuildResume(builder, LLVMBuildLoad(builder, lpContext, ""));
		}
	}
	
	void unwindTo(size_t level) {
		closeBlockTo(level);
		
		bool mustResume = false;
		auto currentBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(currentBB);
		auto preUnwindBB = currentBB;
		
		foreach_reverse(b; unwindBlocks[level .. $]) {
			if (b.kind == BlockKind.Success) {
				continue;
			}
			
			assert(b.kind != BlockKind.Catch);
			
			// We have a scope(exit) or scope(failure).
			// Check if we need to chain unwinding.
			auto unwindBB = b.unwindBB;
			if (!unwindBB) {
				if (!mustResume) {
					continue;
				}
				
				unwindBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unwind");
			}
			
			// We encountered a scope statement that
			// can be reached while unwinding.
			mustResume = true;
			
			// Reorder basic blocks so that IR look nice.
			auto landingPadBB = b.landingPadBB;
			if (landingPadBB) {
				LLVMMoveBasicBlockAfter(landingPadBB, currentBB);
				currentBB = landingPadBB;
			}
			
			LLVMMoveBasicBlockAfter(unwindBB, currentBB);
			LLVMPositionBuilderAtEnd(builder, unwindBB);
			
			auto oldLocals = pass.locals.dup;
			scope(exit) {
				if (pass.locals.length != oldLocals.length) {
					pass.locals = oldLocals;
				}
			}
			
			// Emit the exception cleanup code.
			visit(b.statement);
			
			currentBB = LLVMGetInsertBlock(builder);
		}
		
		unwindBlocks = unwindBlocks[0 .. level];
		if (!mustResume) {
			return;
		}
		
		concludeUnwind(fun, currentBB);
		
		auto resumeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "resume");
		
		if (!LLVMGetBasicBlockTerminator(preUnwindBB)) {
			LLVMPositionBuilderAtEnd(builder, preUnwindBB);
			LLVMBuildBr(builder, resumeBB);
		}
		
		LLVMMoveBasicBlockAfter(resumeBB, currentBB);
		LLVMPositionBuilderAtEnd(builder, resumeBB);
	}
}
