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
	
	size_t continueUnwindBlock;
	size_t breakUnwindBlock;
	
	LLVMBasicBlockRef continueBB;
	LLVMBasicBlockRef breakBB;
	
	LLVMBasicBlockRef[Name] labels;
	
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
	
	private void handleLoop(LoopStatement)(LoopStatement l) {
		enum isFor = is(LoopStatement : ForStatement);
		enum isDoWhile = is(LoopStatement : DoWhileStatement);
		
		// Generate initialization if appropriate
		static if(isFor) {
			auto oldUnwindBlocks = unwindBlocks;
			scope(exit) unwindBlocks = oldUnwindBlocks;
			
			visit(l.initialize);
		}
		
		auto oldBreakUnwindBlock = breakUnwindBlock;
		auto oldContinueUnwindBlock = continueUnwindBlock;
		
		auto oldBreakBB = breakBB;
		auto oldContinueBB = continueBB;
		
		scope(exit) {
			breakUnwindBlock = oldBreakUnwindBlock;
			continueUnwindBlock = oldContinueUnwindBlock;
			
			breakBB = oldBreakBB;
			continueBB = oldContinueBB;
		}
		
		breakUnwindBlock = unwindBlocks.length;
		continueUnwindBlock = unwindBlocks.length;
		
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		static if(isFor) {
			auto testBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "for");
			continueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "increment");
		} else {
			continueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "while");
			auto testBB = continueBB;
		}
		
		auto doBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "do");
		
		breakBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "done");
		
		static if(isDoWhile) {
			alias startBB = doBB;
		} else {
			alias startBB = testBB;
		}
		
		// Jump into the loop.
		LLVMBuildBr(builder, startBB);
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
	
	void visit(BreakStatement s) {
		assert(breakBB);
		
		rewindTo(breakUnwindBlock);
		
		if(!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			LLVMBuildBr(builder, breakBB);
		}
	}
	
	void visit(ContinueStatement s) {
		assert(continueBB);
		
		rewindTo(continueUnwindBlock);
		
		if(!LLVMGetBasicBlockTerminator(LLVMGetInsertBlock(builder))) {
			LLVMBuildBr(builder, continueBB);
		}
	}
	
	void visit(SwitchStatement s) {
		auto oldBreakUnwindBlock = breakUnwindBlock;
		
		scope(exit) {
			breakUnwindBlock = oldBreakUnwindBlock;
		}
		
		breakUnwindBlock = unwindBlocks.length;
		
		auto expression = genExpression(s.expression);
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		auto oldDefault = labels.get(BuiltinName!"default", null);
		scope(exit) {
			if(oldDefault) {
				labels[BuiltinName!"default"] = oldDefault;
			} else {
				labels.remove(BuiltinName!"default");
			}
		}
		
		auto defaultBB = labels[BuiltinName!"default"] = LLVMAppendBasicBlockInContext(llvmCtx, fun, "default");
		auto startBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "switchstart");
		
		auto oldBreakBB = breakBB;
		scope(exit) breakBB = oldBreakBB;
		
		breakBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "switchend");
		
		auto oldSwitchInstr = switchInstr;
		scope(exit) switchInstr = oldSwitchInstr;
		
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
	
	void visit(CaseStatement s) {
		assert(switchInstr);
		
		auto currentBB = LLVMGetInsertBlock(builder);
		auto caseBB = getLabel(BuiltinName!"case");
		labels.remove(BuiltinName!"case");
		
		LLVMMoveBasicBlockAfter(caseBB, currentBB);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMBuildBr(builder, caseBB);
		}
		
		foreach(e; s.cases) {
			LLVMAddCase(switchInstr, genExpression(e), caseBB);
		}
		
		LLVMPositionBuilderAtEnd(builder, caseBB);
	}
	
	private auto getLabel(Name label) {
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		return labels.get(label, labels[label] = LLVMAppendBasicBlockInContext(llvmCtx, fun, toStringz("." ~ label.toString(context))));
	}
	
	void visit(LabeledStatement s) {
		auto currentBB = LLVMGetInsertBlock(builder);
		
		auto labelBB = getLabel(s.label);
		LLVMMoveBasicBlockAfter(labelBB, currentBB);
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(currentBB)) {
			LLVMBuildBr(builder, labelBB);
		}
		
		LLVMPositionBuilderAtEnd(builder, labelBB);
		
		visit(s.statement);
	}
	
	void visit(GotoStatement s) {
		auto labelBB = getLabel(s.label);
		
		LLVMBuildBr(builder, labelBB);
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

