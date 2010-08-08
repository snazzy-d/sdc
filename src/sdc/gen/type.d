/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import std.string;

import llvm.c.Core;

import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;


enum DType
{
    None,
    Bool,
    Int,
    Function,
}

abstract class Type
{
    DType dtype;
    
    this(Module mod)
    {
        mModule = mod;
    }
    
    LLVMTypeRef llvmType()
    {
        return mType;
    }
    
    protected Module mModule;
    protected LLVMTypeRef mType;
}

class BoolType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Bool;
        mType = LLVMInt1TypeInContext(mod.context);
    }
}

class IntType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Int;
        mType = LLVMInt32TypeInContext(mod.context);
    }
}

class FunctionType : Type
{
    this(Module mod, ast.FunctionDeclaration funcDecl)
    {
        super(mod);
        dtype = DType.Function;
        mFunctionDeclaration = funcDecl;
    }
    
    void declare()
    {
        auto retval = astTypeToBackendType(mFunctionDeclaration.retval, mModule);
        LLVMTypeRef[] params;
        foreach (param; mFunctionDeclaration.parameters) {
            mParameters ~= astTypeToBackendType(param.type, mModule);
            params ~= mParameters[$ - 1].llvmType;
        }
        mType = LLVMFunctionType(retval.llvmType, params.ptr, params.length, false);
    }
        
    protected ast.FunctionDeclaration mFunctionDeclaration;
    protected Type[] mParameters;
}
