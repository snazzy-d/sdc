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

final class StatementGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	void visit(Statement s) {
		this.dispatch(s);
	}
	
	void visit(SymbolStatement s) {
		pass.visit(s.symbol);
	}
	
	void visit(ExpressionStatement e) {
		pass.visit(e.expression);
	}
	
	void visit(BlockStatement b) {
		foreach(s; b.statements) {
			visit(s);
		}
	}
	
	void visit(IfStatement ifs) {
		auto condition = pass.visit(ifs.condition);
		
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
		
		// Conclude that block if it isn't already.
		if(!LLVMGetBasicBlockTerminator(thenBB)) {
			LLVMBuildBr(builder, mergeBB);
		}
		
		// Put the else block after the generated stuff.
		LLVMMoveBasicBlockAfter(elseBB, thenBB);
		LLVMPositionBuilderAtEnd(builder, elseBB);
		
		if(ifs.elseStatement) {
			// Emit else
			visit(ifs.elseStatement);
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
		auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
		
		enum isFor = is(LoopStatement : ForStatement);
		enum isDoWhile = is(LoopStatement : DoWhileStatement);
		
		auto oldContinueBB = continueBB;
		scope(exit) continueBB = oldContinueBB;
		
		static if(isFor) {
			auto testBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "for");
			continueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "increment");
		} else {
			continueBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "while");
			auto testBB = continueBB;
		}
		
		auto doBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "do");
		
		auto oldBreakBB = breakBB;
		scope(exit) breakBB = oldBreakBB;
		
		breakBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "done");
		
		static if(isDoWhile) {
			alias doBB startBB;
		} else {
			alias testBB startBB;
		}
		
		// Generate initialization if appropriate
		static if(isFor) {
			visit(l.initialize);
		}
		
		// Jump into the loop.
		LLVMBuildBr(builder, startBB);
		LLVMPositionBuilderAtEnd(builder, testBB);
		
		// Test and do or jump to done.
		auto condition = pass.visit(l.condition);
		LLVMBuildCondBr(builder, condition, doBB, breakBB);
		
		// Build continue block or alias it to the test.
		static if(isFor) {
			LLVMPositionBuilderAtEnd(builder, continueBB);
			pass.visit(l.increment);
			
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
		import d.ir.expression;
		LLVMBuildRet(builder, pass.visit(r.value));
	}
	
	void visit(BreakStatement s) {
		assert(breakBB);
		LLVMBuildBr(builder, breakBB);
	}
	
	void visit(ContinueStatement s) {
		assert(continueBB);
		LLVMBuildBr(builder, continueBB);
	}
	
	void visit(SwitchStatement s) {
		auto expression = pass.visit(s.expression);
		
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
			LLVMAddCase(switchInstr, pass.visit(e), caseBB);
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
}

