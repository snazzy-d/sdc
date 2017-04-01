module d.llvm.statement;

import d.llvm.local;

import d.ir.expression;
import d.ir.instruction;

import d.context.location;

import util.visitor;

import llvm.c.core;

struct StatementGen {
	private LocalPass pass;
	alias pass this;
	
	LLVMValueRef fun;
	
	LLVMBasicBlockRef[] basicBlocks;
	LLVMBasicBlockRef[] landingPads;
	
	Body fbody;
	
	this(LocalPass pass) {
		this.pass = pass;
	}
	
	void visit(Body fbody) in {
		assert(fbody, "Empty body");
	} body {
		basicBlocks.length = fbody.length;
		landingPads.length = fbody.length;
		
		auto allocaBB = LLVMGetInsertBlock(builder);
		fun = LLVMGetBasicBlockParent(allocaBB);
		scope(success) {
			// Branch from alloca block to function body.
			LLVMPositionBuilderAtEnd(builder, allocaBB);
			LLVMBuildBr(builder, basicBlocks[0]);
		}
		
		this.fbody = fbody;
		foreach (b; range(fbody)) {
			visit(b);
		}
	}
	
	void visit(BasicBlockRef b) {
		auto llvmBB = genBasicBlock(b);
		LLVMMoveBasicBlockAfter(llvmBB, LLVMGetInsertBlock(builder));
		LLVMPositionBuilderAtEnd(builder, llvmBB);
		
		lpBB = genLandingPad(b);
		
		foreach(i; range(fbody, b)) {
			final switch(i.op) with(OpCode) {
				case Alloca:
					define(i.var);
					break;
				
				case Destroy:
					auto v = i.var;
					auto s = v.type.getCanonical().dstruct;
					assert(!s.isPod, "struct is not a pod");
					
					import d.context.name;
					auto dsym = s.resolve(i.location, BuiltinName!"__dtor");
					
					import d.ir.symbol;
					auto dtor = cast(Function) dsym;
					if (dtor is null) {
						auto os = cast(OverloadSet) dsym;
						assert(os, "__dtor must be an overload set");
						dtor = cast(Function) os.set[0];
					}
					
					assert(dtor, "Cannot find dtor");
					genCall(declare(dtor), [declare(v)]);
					break;
				
				case Evaluate:
					genExpression(i.expr);
					break;
				
				// FIXME: Delete this, we can generate these upon use.
				case Declare:
					define(i.sym);
					break;
			}
		}
		
		auto bb = &fbody[b];
		final switch(bb.terminator) with(Terminator) {
			case None:
				assert(0, "Unterminated block");
			
			case Branch:
				if (bb.value) {
					LLVMBuildCondBr(
						builder,
						genExpression(bb.value),
						genBasicBlock(fbody[b].successors[0]),
						genBasicBlock(fbody[b].successors[1]),
					);
				} else {
					LLVMBuildBr(
						builder,
						genBasicBlock(fbody[b].successors[0]),
					);
				}
				
				break;
			
			case Switch:
				auto switchTable = bb.switchTable;
				auto e = genExpression(bb.value);
				auto switchInstr = LLVMBuildSwitch(
					builder,
					e,
					genBasicBlock(switchTable.defaultBlock),
					switchTable.entryCount,
				);
				
				auto t = LLVMTypeOf(e);
				foreach(c; switchTable.cases) {
					LLVMAddCase(
						switchInstr,
						LLVMConstInt(t, c.value, false),
						genBasicBlock(c.block),
					);
				}
				
				break;
			
			case Return:
				if (bb.value) {
					auto ret = genExpression(bb.value);
					LLVMBuildRet(builder, ret);
				} else {
					LLVMBuildRetVoid(builder);
				}
				
				break;
			
			case Throw:
				if (bb.value) {
					genCall(
						declare(pass.object.getThrow()),
						[genExpression(bb.value)],
					);
					LLVMBuildUnreachable(builder);
					break;
				}
				
				// Create an alloca for the landing pad results.
				if (!lpContext) {
					auto currentBB = LLVMGetInsertBlock(builder);
					LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(fun));
					lpContext = LLVMBuildAlloca(builder, getLpType(), "lpContext");
					LLVMPositionBuilderAtEnd(builder, currentBB);
					LLVMSetPersonalityFn(fun, declare(pass.object.getPersonality()));
				}
				
				auto catchTable = fbody[b].catchTable;
				if (catchTable is null) {
					Resume:
					if (auto lpBlock = fbody[b].landingpad) {
						LLVMBuildBr(builder, genBasicBlock(lpBlock));
					} else {
						auto lp = LLVMBuildLoad(builder, lpContext, "");
						LLVMBuildResume(builder, lp);
					}
					
					break;
				}
				
				auto i32 = LLVMInt32TypeInContext(llvmCtx);
				LLVMValueRef[2] gepIdx = [
					LLVMConstInt(i32, 0, false),
					LLVMConstInt(i32, 1, false),
				];
				
				auto ptr = LLVMBuildInBoundsGEP(
					builder,
					lpContext,
					gepIdx.ptr,
					gepIdx.length,
					"",
				);
				
				import d.llvm.runtime;
				auto ehTypeidFun = RuntimeGen(pass.pass).getEhTypeidFor();
				
				auto actionid = LLVMBuildLoad(builder, ptr, "actionid");
				auto i8 = LLVMInt8TypeInContext(llvmCtx);
				auto voidstar = LLVMPointerType(i8, 0);
				foreach(c; catchTable.catches) {
					auto nextUnwindBB =
						LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
					
					import d.llvm.type;
					auto typeinfo = LLVMBuildBitCast(
						builder,
						TypeGen(pass.pass).getTypeInfo(c.type),
						voidstar,
						"",
					);
					
					LLVMBuildCondBr(
						builder,
						LLVMBuildICmp(
							builder,
							LLVMIntPredicate.EQ,
							genCall(ehTypeidFun, [typeinfo]),
							actionid,
							"",
						),
						genBasicBlock(c.block),
						nextUnwindBB,
					);
					
					LLVMPositionBuilderAtEnd(builder, nextUnwindBB);
				}
				
				auto lpBlock = fbody[b].landingpad;
				if (lpBlock) {
					LLVMBuildBr(builder, genBasicBlock(lpBlock));
					break;
				}
				
				goto Resume;
			
			case Halt:
				genHalt(bb.location, bb.value);
				break;
		}
	}
	
	private auto genExpression(Expression e) {
		import d.llvm.expression;
		return ExpressionGen(pass).visit(e);
	}
	
	private auto getLpType() {
		LLVMTypeRef[2] lpTypes = [
			LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0),
			LLVMInt32TypeInContext(llvmCtx),
		];
		
		return LLVMStructTypeInContext(
			llvmCtx,
			lpTypes.ptr,
			lpTypes.length,
			false,
		);
	}
	
	private LLVMBasicBlockRef genLandingPad(BasicBlockRef srcBlock) {
		auto b = fbody[srcBlock].landingpad;
		if (!b) {
			return null;
		}
		
		auto i = *(cast(uint*) &b) - 1;
		if (landingPads[i] !is null) {
			return landingPads[i];
		}
		
		// We have a failure case.
		auto currentBB = LLVMGetInsertBlock(builder);
		scope(exit) LLVMPositionBuilderAtEnd(builder, currentBB);
		
		auto lpType = getLpType();
		
		// Create an alloca for the landing pad results.
		if (!lpContext) {
			LLVMPositionBuilderAtEnd(builder, LLVMGetFirstBasicBlock(fun));
			lpContext = LLVMBuildAlloca(builder, lpType, "lpContext");
			LLVMSetPersonalityFn(fun, declare(pass.object.getPersonality()));
		}
		
		auto lpBB = landingPads[i] = LLVMAppendBasicBlockInContext(
			llvmCtx,
			fun,
			"landingPad",
		);
		
		auto instrs = range(fbody, b);
		auto terminator = fbody[b].terminator;
		bool cleanup = instrs.length > 0 || terminator != Terminator.Throw;
		
		LLVMValueRef[] clauses;
		if (terminator == Terminator.Throw && !fbody[b].value) {
			if (auto catchTable = fbody[b].catchTable) {
				foreach(c; catchTable.catches) {
					import d.llvm.type;
					clauses ~= TypeGen(pass.pass).getTypeInfo(c.type);
				}
			}
		}
		
		if (auto nextLpBB = genLandingPad(b)) {
			auto nextLp = LLVMGetFirstInstruction(nextLpBB);
			cleanup = cleanup || LLVMIsCleanup(nextLp);
			
			clauses.length = LLVMGetNumClauses(nextLp);
			foreach (uint n, ref c; clauses) {
				c = LLVMGetClause(nextLp, n);
			}
		}
		
		LLVMPositionBuilderAtEnd(builder, lpBB);
		auto landingPad = LLVMBuildLandingPad(
			builder,
			lpType,
			null,
			cast(uint) clauses.length,
			"",
		);
		
		LLVMSetCleanup(landingPad, cleanup);
		foreach (c; clauses) {
			LLVMAddClause(landingPad, c);
		}
		
		LLVMBuildStore(builder, landingPad, lpContext);
		LLVMBuildBr(builder, genBasicBlock(b));
		
		return lpBB;
	}
	
	private LLVMBasicBlockRef genBasicBlock(BasicBlockRef b) {
		auto i = *(cast(uint*) &b) - 1;
		if (basicBlocks[i] !is null) {
			return basicBlocks[i];
		}
		
		// Make sure we have the landign pad ready.
		genLandingPad(b);
		
		return basicBlocks[i] = LLVMAppendBasicBlockInContext(
			llvmCtx,
			fun,
			fbody[b].name.toStringz(context),
		);
	}
	
	private auto genCall(LLVMValueRef callee, LLVMValueRef[] args) {
		import d.llvm.expression;
		return ExpressionGen(pass).buildCall(callee, args);
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
			genCall(declare(pass.object.getAssertFailMsg()), args[]);
		} else {
			genCall(declare(pass.object.getAssertFail()), args[1 .. $]);
		}
		
		// Conclude that block.
		LLVMBuildUnreachable(builder);
	}
}
