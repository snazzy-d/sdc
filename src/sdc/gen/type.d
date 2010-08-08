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
    Int,
    Function,
}

abstract class Type
{
    DType dtype;
    LLVMTypeRef llvmType();
}

class Int32Type : Type
{
    this(Module mod)
    {
        dtype = DType.Int;
        mModule = mod;
        mType = LLVMInt32TypeInContext(mod.context);
    }
    
    override LLVMTypeRef llvmType()
    {
        return mType;
    }
    
    protected Module mModule;
    protected LLVMTypeRef mType;
}

class FunctionType : Type
{
    this(Module mod, ast.FunctionDeclaration funcDecl)
    {
        dtype = DType.Function;
        mModule = mod;
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
    
    override LLVMTypeRef llvmType()
    {
        return mType;
    }
        
    protected Module mModule;
    protected LLVMTypeRef mType;
    protected ast.FunctionDeclaration mFunctionDeclaration;
    protected Type[] mParameters;
}
