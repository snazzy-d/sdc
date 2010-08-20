/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.sdcmodule;

import std.process;
import std.string;

import llvm.c.Analysis;
import llvm.c.BitWriter;
import llvm.c.Core;
import llvm.c.transforms.Scalar;

import sdc.gen.type;
import sdc.gen.value;


/**
 * Module encapsulates the code generated for a module.
 */ 
class Module
{
    LLVMContextRef context;
    LLVMModuleRef  mod;
    LLVMBuilderRef builder;
    Scope globalScope;
    Scope currentScope;
    Path currentPath;
    Value currentFunction;
    Value base;
    ast.Linkage currentLinkage = ast.Linkage.ExternD;

    
    this(string name)
    {
        context = LLVMGetGlobalContext();
        mod     = LLVMModuleCreateWithNameInContext(toStringz(name), context);
        builder = LLVMCreateBuilderInContext(context);
        
        globalScope = new Scope();
        currentScope = globalScope;
    }
        
    ~this()
    {
        LLVMDisposeModule(mod);
        LLVMDisposeBuilder(builder);
    }
    
    /**
     * Verify that the generated bit code is correct.
     * If it isn't, an error will be printed and the process will be aborted.
     */
    void verify()
    {
        LLVMVerifyModule(mod, LLVMVerifierFailureAction.AbortProcess, null);
    }
    
    /**
     * Dump a human readable form of the generated code to stderr.
     */
    void dump()
    {
        LLVMDumpModule(mod);
    }
    
    /**
     * Write the bitcode to a specified file.
     */
    void writeBitcodeToFile(string filename)
    {
        LLVMWriteBitcodeToFile(mod, toStringz(filename));
    }
    
    void writeNativeAssemblyToFile(string fromFilename, string toFilename)
    {
        system(format("llc -o %s %s", toFilename, fromFilename));
    }
    
    /**
     * Optimise the generated code in place.
     */
    void optimise()
    {
        auto passManager = LLVMCreatePassManager();
        LLVMAddInstructionCombiningPass(passManager);
        LLVMAddPromoteMemoryToRegisterPass(passManager);
        LLVMRunPassManager(passManager, mod);
        LLVMDisposePassManager(passManager);
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
    
    Store search(string name)
    {
        /* This isn't just `foreach (localScope; retro(mScopeStack))`  
         * because of a bug manifested in std.range.retro.
         * WORKAROUND 2.048
         */
        for (int i = mScopeStack.length - 1; i >= 0; i--) {
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

enum StoreType
{
    Value,
    Type,
}

class Store
{
    StoreType storeType;
    Object object;
    
    this(Value store)
    {
        storeType = StoreType.Value;
        object = store;
    }
    
    this(Type type)
    {
        storeType = StoreType.Type;
        object = type;
    }
    
    Value value() @property
    {
        assert(storeType == StoreType.Value);
        auto val = cast(Value) object;
        assert(val);
        return val;
    }
    
    Type type() @property
    {
        assert(storeType == StoreType.Type);
        auto type = cast(Type) object;
        assert(type);
        return type;
    }
}

class Scope
{
    bool topLevelBail;
    
    void add(string name, Store store)
    {
        mSymbolTable[name] = store;
    }
    
    Store get(string name)
    {
        auto p = name in mSymbolTable;
        return p is null ? null : *p;
    }
    
    protected Store[string] mSymbolTable;
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
