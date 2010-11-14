/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * 
 * cfg contains a control flow graph implementation, for the
 * purposes of control flow analysis.
 */
module sdc.gen.cfg;

import llvm.c.Core;


/**
 * A BasicBlock is a consecutive sequence of code.
 */
class BasicBlock
{
    bool isExitBlock  = false;
    
    Edge predecessor;
    Edge[] successors;
    
    LLVMBasicBlockRef llvmBasicBlock;  // Optional.
    
    this() {}
    
    this(Edge predecessor)
    {
        this.predecessor = predecessor;
    }
    
    BasicBlock createSuccessorBlock()
    {
        auto edge  = new Edge();
        auto block = new BasicBlock(edge);
        edge.source = this;
        edge.destination = block;
        successors ~= edge;
        return block;
    }
    
    /** 
     * Is it inevitable that upon reaching the end of this block 
     * that control flow shall be terminated?
     */
    bool inevitableExit()
    {
        return isExitBlock;
    }
}

/**
 * An edge connects one BasicBlock with another.
 */
class Edge
{
    BasicBlock source;
    BasicBlock destination;
}
