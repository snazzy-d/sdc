/**
 * Copyright 2010-2011 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 * 
 * cfg contains a control flow graph implementation, for the
 * purposes of control flow analysis.
 */
module sdc.gen.cfg;

import std.array;
import std.stdio;
import std.typecons;
import llvm.c.Core;


/**
 * A BasicBlock is a consecutive sequence of code, with no branches.
 */
class BasicBlock
{
    string name;
    bool isExitBlock = false;  /// e.g. return, throw, assert(false), etc.
    BasicBlock[] children;     /// Possible paths of control flow.
    
    this(string name)
    {
        this.name = name;
    }
    
    @property bool fallsThrough() {
        if (isExitBlock) return false;
        return mFallThrough;
    }
    
    @property void fallsThrough(bool b)
    {
        mFallThrough = b;
    }
    
    /// Can this block reach the target block, without passing through an exit block?
    bool canReach(BasicBlock target)
    {
        if (this is target) {
            return fallsThrough;
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
            if (child.fallsThrough) {
                blockStack ~= Parent(child, 0);
            }
        } while (blockStack.length > 0);
        return false;
    }
    
    void visualise(File file, int accum = 0)
    {
        if (accum == 0) {
            file.writeln("digraph G {");
        }
        if (children.length == 0) {
            file.writeln(name, accum + 1, ";");
        } else {
            foreach (child; children) {
                file.writeln(name, accum, " -> ", child.name, accum + 1, ";");
            }
            foreach (child; children) {
                child.visualise(file, accum + 1);
            }
        }
        if (accum == 0) {
            file.writeln("\n}");
        }
    }

    protected bool mFallThrough = true;
}
