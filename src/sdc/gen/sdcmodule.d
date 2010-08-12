/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcmodule;

import std.string;

import llvm.c.Core;

import sdc.gen.type;
import sdc.gen.value;


class Module
{
    LLVMContextRef context;
    LLVMModuleRef  mod;
    LLVMBuilderRef builder;
    Scope globalScope;
    Scope currentScope;
    Path currentPath;
    
    this(string name)
    {
        context = LLVMGetGlobalContext();
        mod     = LLVMModuleCreateWithNameInContext(toStringz(name), context);
        builder = LLVMCreateBuilderInContext(context);
        
        globalScope = new Scope();
        currentScope = globalScope;
    }
        
    void dispose()
    {
        LLVMDisposeModule(mod);
        LLVMDisposeBuilder(builder);
    }

    void pushScope()
    {
        mScopeStack ~= new Scope();
        currentScope = mScopeStack[$ - 1];
    }
    
    void popScope()
    {
        assert(mScopeStack.length >= 1);
        mScopeStack = mScopeStack[0 .. $ - 1];
        currentScope = mScopeStack.length >= 1 ? mScopeStack[$ - 1] : globalScope;
    }
    
    Value search(string name)
    {
        /* This isn't just `foreach (localScope; retro(mScopeStack))`  
         * because of a bug manifested in std.range.retro.
         * WORKAROUND 2.048
         */
        for (auto i = mScopeStack.length - 1; i >= 0; i--) {
            auto localScope = mScopeStack[i];
            auto v = localScope.get(name);
            if (v !is null) {
                return v;
            }
        }
        return globalScope.get(name);
    }
    
    void pushPath(PathType type)
    {
        mPathStack ~= new Path(type);
        currentPath = mPathStack[$ - 1];
    }
    
    void popPath()
    {
        assert(mPathStack.length >= 1);
        auto oldPath = currentPath;
        mPathStack = mPathStack[0 .. $ - 1];
        currentPath = mPathStack.length >= 1 ? mPathStack[$ - 1] : null;
        if (oldPath !is null && currentPath !is null && oldPath.type == PathType.Inevitable) {
            currentPath.functionEscaped = oldPath.functionEscaped;
        }
    }
    
    /**
     * Returns: the depth of the current scope.
     *          A value of zero means the current scope is global.
     */
    int scopeDepth() @property
    {
        return mScopeStack.length;
    }
    
    protected Scope[] mScopeStack;
    protected Path[] mPathStack;
}

class Scope
{
    void add(Value val, string name)
    {
        mSymbolTable[name] = val;
    }
    
    Value get(string name)
    {
        auto p = name in mSymbolTable;
        return p is null ? null : *p;
    }
    
    protected Value[string] mSymbolTable;
}

enum PathType
{
    Inevitable,
    Optional,
}

class Path
{
    this(PathType type)
    {
        this.type = type;
    }
    
    PathType type;
    bool functionEscaped;
}
