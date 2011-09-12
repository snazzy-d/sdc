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
    BasicBlock loop, loopout;
    
    public:
    Module mod;
    LLVMBasicBlockRef topBB, bodyBB, endBB, incrementBB;
    
    this(Module mod, string name, LoopStart start = LoopStart.Top)
    {
        this.mod = mod;
        this.topBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "looptop");
        this.bodyBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopbody");
        this.incrementBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopincrement");
        this.endBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.llvmValue, "loopend");
        
        this.loop = new BasicBlock(name);
        this.loopout = new BasicBlock(name ~ "out");
        
        auto parent = mod.currentFunction.cfgTail;
        parent.children ~= loop;
        parent.children ~= loopout;
        loop.children ~= loopout;
        loop.children ~= loop;
        
        LLVMBuildBr(mod.builder, start == LoopStart.Body? bodyBB : topBB);
    }
    
    /**
     * Generate loop.
     * Params:
     *   genTop = generate top. Must not fall through.
     *   genBody = generate body.
     *   genIncrement = generate increment. This is the continue target.
     */
    void gen(scope void delegate() genTop, scope void delegate() genBody, scope void delegate() genIncrement)
    {
        mod.pushLoop(&this);
        
        LLVMPositionBuilderAtEnd(mod.builder, topBB);
        mod.currentFunction.currentBasicBlock = topBB;
        mod.currentFunction.cfgTail = loop;
        genTop();
        
        LLVMPositionBuilderAtEnd(mod.builder, bodyBB);
        mod.currentFunction.currentBasicBlock = bodyBB;
        mod.currentFunction.cfgTail = loop;
        genBody();
        if (mod.currentFunction.cfgTail.fallsThrough) {
            LLVMBuildBr(mod.builder, incrementBB);
        }
        
        LLVMPositionBuilderAtEnd(mod.builder, incrementBB);
        mod.currentFunction.currentBasicBlock = incrementBB;
        mod.currentFunction.cfgTail = loop;
        genIncrement();
        if (mod.currentFunction.cfgTail.fallsThrough) {
            LLVMBuildBr(mod.builder, topBB);
        }
        
        mod.currentFunction.cfgTail = loopout;
        LLVMPositionBuilderAtEnd(mod.builder, endBB);
        mod.currentFunction.currentBasicBlock = endBB;
        
        mod.popLoop();
    }
    
    void genBreak()
    {
        LLVMBuildBr(mod.builder, endBB);
    }
    
    void genContinue()
    {
        LLVMBuildBr(mod.builder, incrementBB);
    }
}
