module d.llvm.statement;

import d.llvm.codegen;

import d.ir.expression;
import d.ir.statement;

import d.context;

import util.visitor;

import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

struct StatementGen {
	private CodeGenPass pass;
	alias pass this;
	
	LLVMValueRef switchInstr;
	
	struct LabelBlock {
		size_t unwind;
		LLVMBasicBlockRef basic;
	}
	
	LabelBlock continueBlock;
	LabelBlock breakBlock;
	LabelBlock defaultBlock;
	
	LabelBlock[Name] labels;
	
	// Forward goto can only be resolved when the label is reached.
	struct GotoBlock {
		CodeGenPass.Block[] unwind;
		LLVMBasicBlockRef basic;
	}
	
	GotoBlock[][Name] inFlightGotos;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(SymbolStatement s) {
		pass.visit(s.symbol);
	}
	
	private auto genExpression(Expression e) {
		import d.llvm.expression;
		auto eg = ExpressionGen(pass);
		return eg.visit(e);
	}
	
	void visit(ExpressionStatement e) {
		genExpression(e.expression);
	}
	
	void rewindTo(size_t level) {
		auto oldUnwindBlocks = unwindBlocks;
		scope(exit) unwindBlocks = oldUnwindBlocks;
		
		while(unwindBlocks.length > level) {
			auto b = unwindBlocks.back;
			unwindBlocks.popBack();
			
			if(b.kind == BlockKind.Exit || b.kind == BlockKind.Success) {
				if(LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
					break;
				}
				
				visit(b.statement);
			}
		}
	}
	
	void concludeUnwind(LLVMValueRef fun, LLVMBasicBlockRef currentBB) {
		if(!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMPositionBuilderAtEnd(builder, currentBB);
			foreach_reverse(b; unwindBlocks) {
				if(b.kind == BlockKind.Success) {
					continue;
				}
				
				if(!b.unwindBB) {
					b.unwindBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unwind");
				}
				
				LLVMBuildBr(builder, b.unwindBB);
				break;
			}
			
			if(!LLVMGetBasicBlockTerminator(currentBB)) {
				LLVMBuildResume(builder, LLVMBuildLoad(builder, lpContext, ""));
			}
		}
	}
	
	void unwindTo(size_t level) {
		rewindTo(level);
		
		bool mustResume = false;
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		auto currentBB = LLVMGetInsertBlock(builder);
		auto preUnwindBB = currentBB;
		
		foreach_reverse(b; unwindBlocks[level .. $]) {
			if(b.kind == BlockKind.Success) {
				continue;
			}
			
			assert(b.kind != BlockKind.Catch);
			
			auto unwindBB = b.unwindBB;
			if(!unwindBB) {
				if(!mustResume) {
					continue;
				}
				
				unwindBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "unwind");
			}
			
			mustResume = true;
			
			auto landingPadBB = b.landingPadBB;
			if(landingPadBB) {
				LLVMMoveBasicBlockAfter(landingPadBB, currentBB);
				currentBB = landingPadBB;
			}
			
			LLVMMoveBasicBlockAfter(unwindBB, currentBB);
			LLVMPositionBuilderAtEnd(builder, unwindBB);
			
			visit(b.statement);
			
			currentBB = LLVMGetInsertBlock(builder);
		}
		
		unwindBlocks = unwindBlocks[0 .. level];
		if(!mustResume) {
			return;
		}
		
		concludeUnwind(fun, currentBB);
		
		auto resumeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "resume");
		
		if(!LLVMGetBasicBlockTerminator(preUnwindBB)) {
			LLVMPositionBuilderAtEnd(builder, preUnwindBB);
			LLVMBuildBr(builder, resumeBB);
		}
		
		LLVMMoveBasicBlockAfter(resumeBB, currentBB);
		LLVMPositionBuilderAtEnd(builder, resumeBB);
	}
	
	void visit(BlockStatement b) {
		auto oldUnwindBlocks = unwindBlocks;
		
		foreach(s; b.statements) {
			visit(s);
		}
		
		unwindTo(oldUnwindBlocks.length);
	}
	
	void visit(IfStatement ifs) {
		auto oldUnwindBlocks = unwindBlocks;
		scope(exit) unwindBlocks = oldUnwindBlocks;
		
		auto condition = genExpression(ifs.condition);
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto thenBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "then");
		auto elseBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "else");
		auto mergeBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "merge");
		
		LLVMBuildCondBr(builder, condition, thenBB, elseBB);
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, thenBB);
		
		visit(ifs.then);
		unwindTo(oldUnwindBlocks.length);
		
		// Codegen of then can change the current block, so we put everything in order.
		thenBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(thenBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		// Put the else block after the generated stuff.
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		if(ifs.elseStatement) {
			unwindBlocks = oldUnwindBlocks;
			
			// Emit else
			visit(ifs.elseStatement);
			unwindTo(oldUnwindBlocks.length);
		}
		
		// Codegen of else can change the current block, so we put everything in order.
		elseBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(elseBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		LLVMMoveBasicBlockAfter(mergeBB, elseBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
	}
	
	private void maybeBranchTo(LLVMBasicBlockRef destBB) {
		if (!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			LLVMBuildBr(builder, destBB);
		}
	}
	
	private void handleLoop(LoopStatement)(LoopStatement l) {
		enum isFor = is(LoopStatement : ForStatement);
		enum isDoWhile = is(LoopStatement : DoWhileStatement);
		
		// Generate initialization if appropriate
		static if(isFor) {
			auto oldUnwindBlocks = unwindBlocks;
			scope(exit) unwindBlocks = oldUnwindBlocks;
			
			visit(l.initialize);
		}
		
		auto oldBreakBlock = breakBlock;
		auto oldContinueBlock = continueBlock;
		
		scope(exit) {
			breakBlock = oldBreakBlock;
			continueBlock = oldContinueBlock;
		}
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		static if(isFor) {
			auto testBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "for");
			auto continueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "increment");
		} else {
			auto continueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "while");
			auto testBB = continueBB;
		}
		
		auto doBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "do");
		auto breakBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "done");
		
		breakBlock = LabelBlock(unwindBlocks.length, breakBB);
		continueBlock = LabelBlock(unwindBlocks.length, continueBB);
		
		static if(isDoWhile) {
			alias startBB = doBB;
		} else {
			alias startBB = testBB;
		}
		
		// Jump into the loop.
		maybeBranchTo(startBB);
		LLVMPositionBuilderAtEnd(builder, testBB);
		
		// Test and do or jump to done.
		auto condition = genExpression(l.condition);
		LLVMBuildCondBr(builder, condition, doBB, breakBB);
		
		// Build continue block or alias it to the test.
		static if(isFor) {
			LLVMPositionBuilderAtEnd(builder, continueBB);
			genExpression(l.increment);
			
			LLVMBuildBr(builder, testBB);
		}
		
		// Emit do
		LLVMPositionBuilderAtEnd(builder, doBB);
		
		visit(l.statement);
		
		// Codegen of then can change the current block, so we put everything in order.
		doBB = LLVMGetInsertBlock(builder);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(doBB)) {
			LLVMBuildBr(builder, continueBB);
		}
		
		LLVMMoveBasicBlockAfter(breakBB, doBB);
		LLVMPositionBuilderAtEnd(builder, breakBB);
		
		static if(isFor) {
			unwindTo(oldUnwindBlocks.length);
		}
	}
	
	void visit(WhileStatement w) {
		handleLoop(w);
	}
	
	void visit(DoWhileStatement w) {
		handleLoop(w);
	}
	
	void visit(ForStatement f) {
		handleLoop(f);
	}
	
	void visit(ReturnStatement r) {
		auto ret = genExpression(r.value);
		
		rewindTo(0);
		
		if(!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			LLVMBuildRet(builder, ret);
		}
	}
	
	private void unwindAndBranch(LabelBlock b) in {
		assert(b.basic !is null);
	} body {
		rewindTo(b.unwind);
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
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(finalBB)) {
			LLVMBuildBr(builder, breakBB);
		}
		
		// Conclude default block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(defaultBB)) {
			LLVMPositionBuilderAtEnd(builder, defaultBB);
			LLVMBuildUnreachable(builder);
		}
		
		LLVMMoveBasicBlockAfter(breakBB, finalBB);
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
		fixupGoto(BuiltinName!"case", LabelBlock(unwindBlocks.length, caseBB));
		
		LLVMMoveBasicBlockAfter(caseBB, currentBB);
		
		// Conclude that block if it isn't already.
		if (!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMPositionBuilderAtEnd(builder, currentBB);
			LLVMBuildBr(builder, caseBB);
		}
		
		foreach(e; s.cases) {
			LLVMAddCase(switchInstr, genExpression(e), caseBB);
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
			auto fun = LLVMGetBasicBlockParent(currentBB);
			labelBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, toStringz("." ~ label.toString(context)));
			
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
	
	void visit(ThrowStatement s) {
		import d.llvm.expression;
		auto eg = ExpressionGen(pass);
		auto value = LLVMBuildBitCast(builder, eg.visit(s.value), pass.visit(pass.object.getThrowable()), "");
		
		eg.buildCall(pass.visit(pass.object.getThrow()), [value]);
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
			buildClassType(type);
			catchClauses ~= getTypeInfo(type);
			
			unwindBlocks ~= Block(BlockKind.Catch, c.statement, null, null);
		}
		
		visit(s.statement);
		
		auto currentBB = LLVMGetInsertBlock(builder);
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMBuildBr(builder, resumeBB);
		}
		
		auto lastBlock = unwindBlocks[$ - 1];
		unwindBlocks = unwindBlocks[0 .. $ - catches.length];
		
		scope(success) {
			LLVMPositionBuilderAtEnd(builder, resumeBB);
		}
		
		// If no unwind in the first block, we can skip the whole stuff.
		auto unwindBB = lastBlock.unwindBB;
		if(!unwindBB) {
			LLVMMoveBasicBlockAfter(resumeBB, currentBB);
			return;
		}
		
		// Only the first one can have a landingPad.
		auto landingPadBB = lastBlock.landingPadBB;
		if(landingPadBB) {
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
			
			import d.llvm.expression;
			auto eg = ExpressionGen(pass);
			auto typeinfo = LLVMBuildBitCast(builder, getTypeInfo(c.type), LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0), "");
			auto tid = eg.buildCall(druntimeGen.getEhTypeidFor(), [typeinfo]);
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.EQ, tid, cid, "");
			LLVMBuildCondBr(builder, condition, catchBB, nextUnwindBB);
			
			LLVMMoveBasicBlockAfter(catchBB, unwindBB);
			LLVMPositionBuilderAtEnd(builder, catchBB);
			
			visit(c.statement);
			
			currentBB = LLVMGetInsertBlock(builder);
			if(!LLVMGetBasicBlockTerminator(currentBB)) {
				LLVMBuildBr(builder, resumeBB);
			}
			
			unwindBB = nextUnwindBB;
			LLVMPositionBuilderAtEnd(builder, unwindBB);
		}
		
		LLVMMoveBasicBlockAfter(resumeBB, unwindBB);
		concludeUnwind(fun, unwindBB);
	}
}

