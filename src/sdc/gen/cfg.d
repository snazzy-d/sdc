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


/**
 * A BasicBlock is a consecutive sequence of code, with no branches.
 */
class BasicBlock
{
    string name;
    bool isExitBlock = false;  /// e.g. return, throw, assert(false), etc.
    BasicBlock[] children;     /// Possible paths of control flow.
    bool isUnreachableBlock = false; /// Dummy block inserted *after* an exit block.
    
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
        bool[BasicBlock] considered;
        BasicBlock[] Q;
        Q ~= this;
        considered[this] = true;
        
        while (!Q.empty) {
            auto node = Q.front;
            Q.popFront;
            if (node is target) {
                return true;
            }
            if (!node.isExitBlock) foreach (child; node.children) {
                if (!(child in considered)) {
                    Q ~= child;
                    considered[child] = true;
                }
            }
        }
        
        return false;
    }
    
    void visualise(File file = stdout, int accum = 0)
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
