/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;


enum DType
{
    None,
    Bool,
    Int,
    Complex,
    Function,
}

pure bool isComplexDType(DType dtype)
{
    return dtype >= DType.Complex;
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
    
    /// An opEquals appropriate for simple types.
    override bool opEquals(Object o)
    {
        auto asType = cast(Type) o;
        if (!asType) return false;
        
        return this.mType == asType.mType;
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
    Type returnType;
    Type[] argumentTypes;
    
    this(Module mod, ast.FunctionDeclaration funcDecl)
    {
        super(mod);
        dtype = DType.Function;
        mFunctionDeclaration = funcDecl;
    }
    
    void declare()
    {
        auto retval = astTypeToBackendValue(mFunctionDeclaration.retval, mModule);
        returnType = retval.type;
        LLVMTypeRef[] params;
        foreach (param; mFunctionDeclaration.parameters) {
            auto val = astTypeToBackendValue(param.type, mModule);
            argumentTypes ~= val.type;
            params ~= val.type.llvmType;
        }
        mType = LLVMFunctionType(retval.type.llvmType, params.ptr, params.length, false);
    }

    protected ast.FunctionDeclaration mFunctionDeclaration;
}

unittest
{
    auto mod = new Module("unittest_module");
    auto a = new IntType(mod);
    auto b = new IntType(mod);
    assert(a !is b);
    assert(a == b);
    auto c = new BoolType(mod);
    assert(a != c);
    mod.dispose();
}
