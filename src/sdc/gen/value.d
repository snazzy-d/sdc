/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.value;

import std.string;

import llvm.c.Core;

import sdc.extract.base;
import sdc.gen.sdcmodule;
import sdc.gen.type;


interface Value
{
    Type type();
    LLVMValueRef get();
    void set(Value val);
}

class IntegerValue(T, R) : Value
{
    bool constant;
    R constVal;
    
    
    this(Module mod)
    {
        mModule = mod;
        mType = new T(mod);
        mValue = LLVMBuildAlloca(mod.builder, mType.llvmType(), "int");
    }
    
    this(Module mod, ast.IntegerLiteral integerLiteral)
    {
        this(mod);
        constVal = extractIntegerLiteral(integerLiteral);
        auto val = LLVMConstInt(mType.llvmType(), constVal, false);
        LLVMBuildStore(mod.builder, val, mValue);
        constant = true;
    }
    
    Type type()
    {
        return mType;
    }
    
    LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "int");
    }
    
    void set(Value val)
    {
        LLVMBuildStore(mModule.builder, val.get(), mValue);
    }
    
    protected Module mModule;
    protected Type mType;
    protected LLVMValueRef mValue;
}

alias IntegerType!LLVMInt32TypeInContext Int32Type;
alias IntegerValue!(Int32Type, int) Int32Value;

class FunctionValue : Value
{
    this(Module mod, FunctionType func, string name)
    {
        mModule = mod;
        mFunctionType = func;
        mName = name;
        mValue = LLVMAddFunction(mod.mod, toStringz(name), func.llvmType);
    }
    
    Type type()
    {
        return mFunctionType;
    }
    
    LLVMValueRef get()
    {
        return mValue;
    }
    
    void set(Value val)
    {
    }
    
    protected Module mModule;
    protected FunctionType mFunctionType;
    protected LLVMValueRef mValue;
    protected string mName;
}
