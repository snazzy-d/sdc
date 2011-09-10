/**
 * Copyright 2011 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.loop;

import llvm.c.Core;

import sdc.compilererror;
import sdc.gen.sdcmodule;
import sdc.gen.cfg;
import sdc.gen.expression;
import sdc.gen.statement;
import ast = sdc.ast.all;

enum LoopStart
{
    Top,
    Body
}

struct Loop
{
    private:
    BasicBlock looptop, loopout;
    
    public:
    Module mod;
    LLVMBasicBlockRef topBB, bodyBB, endBB;
    
    this(Module mod, string name, LoopStart start = LoopStart.Top)
    {
        this.mod = mod;
        this.topBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "looptop");
        this.bodyBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopbody");
        this.endBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopend");
        
        auto parent  = mod.currentFunction.cfgTail;
        looptop = new BasicBlock(name ~ "top");
        loopout = new BasicBlock(name ~ "out");
        parent.children ~= looptop;
        parent.children ~= loopout;
        looptop.children ~= loopout;
        looptop.children ~= looptop;
        
        LLVMBuildBr(mod.builder, start == LoopStart.Body? bodyBB : topBB);
    }

    void gen(scope void delegate() genTop, scope void delegate() genBody)
    {
        LLVMPositionBuilderAtEnd(mod.builder, topBB);
        mod.currentFunction.currentBasicBlock = topBB;
        genTop();
        LLVMPositionBuilderAtEnd(mod.builder, bodyBB);
        mod.currentFunction.currentBasicBlock = bodyBB;
        
        mod.currentFunction.cfgTail = looptop;
        genBody();
        if (mod.currentFunction.cfgTail.fallsThrough) {
            LLVMBuildBr(mod.builder, topBB);
        }
        
        mod.currentFunction.cfgTail = loopout;
        LLVMPositionBuilderAtEnd(mod.builder, endBB);
        mod.currentFunction.currentBasicBlock = endBB;
    }
}
