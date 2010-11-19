/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * 
 * cfg contains a control flow graph implementation, for the
 * purposes of control flow analysis.
 */
module sdc.gen.cfg;

import std.array;
import std.typecons;


/**
 * A BasicBlock is a consecutive sequence of code.
 */
class BasicBlock
{
    bool isExitBlock = false;
    BasicBlock[] children;
    
    bool canReachWithoutExit(BasicBlock target)
    {
        if (this is target) {
            return !isExitBlock;
        }
        alias Tuple!(BasicBlock, "node", size_t, "childToSearch") Parent;
        Parent[] blockStack;
        bool[BasicBlock] considered;
        blockStack ~= Parent(this, 0);
        do {
            if (blockStack[$ - 1].node is target) {
                return true;
            }
            considered[blockStack[$ - 1].node] = true;
            if (blockStack[$ - 1].childToSearch >= blockStack[$ - 1].node.children.length) {
                blockStack.popBack;
                continue;
            }
            auto child = blockStack[$ - 1].node.children[blockStack[$ - 1].childToSearch];
            blockStack[$ - 1].childToSearch++;
            if ((child in considered) !is null) {
                continue;
            }
            if (!child.isExitBlock) {
                blockStack ~= Parent(child, 0);            
            }
        } while (blockStack.length > 0);
        return false;
    }
}
