/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.value;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.extract.base;
import sdc.gen.sdcmodule;
import sdc.gen.type;


abstract class Value
{
    bool constant;
    union
    {
        int constInt;
    }
    
    Type type();
    LLVMValueRef get();
    void set(Value val);
    void add(Value val);
    Value init();
}

class Int32Value : Value
{
    this(Module mod)
    {
        mModule = mod;
        mType = new Int32Type(mod);
        mValue = LLVMBuildAlloca(mod.builder, mType.llvmType(), "int");
    }
    
    this(Module mod, ast.IntegerLiteral integerLiteral)
    {
        this(mod);
        constInt = extractIntegerLiteral(integerLiteral);
        constInit(constInt);
    }
    
    this(Module mod, int constInitialiser)
    {
        this(mod);
        constInit(constInitialiser);
    }
    
    this(Module mod, Value val)
    {
        this(mod);
        set(val);
    }
    
    override Type type()
    {
        return mType;
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "int");
    }
    
    override void set(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            this.constInt = val.constInt;
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
    }
    
    override void add(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            this.constInt = this.constInt + val.constInt;
        }
        auto result = LLVMBuildAdd(mModule.builder, this.get(), val.get(), "add");
        LLVMBuildStore(mModule.builder, result, mValue);
    }
    
    override Value init()
    {
        return new Int32Value(mModule, 0);
    }
    
    protected void constInit(int n)
    {
        auto val = LLVMConstInt(mType.llvmType(), n, false);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
    }
    
    protected Module mModule;
    protected Type mType;
    protected LLVMValueRef mValue;
}


class FunctionValue : Value
{
    this(Module mod, FunctionType func, string name)
    {
        mModule = mod;
        mFunctionType = func;
        mName = name;
        mValue = LLVMAddFunction(mod.mod, toStringz(name), func.llvmType);
    }
    
    override Type type()
    {
        return mFunctionType;
    }
    
    override LLVMValueRef get()
    {
        return mValue;
    }
    
    override void set(Value val)
    {
    }
    
    override void add(Value val)
    {
    }
    
    override Value init()
    {
        panic("tried to get the init of a function value.");
        assert(false);
    }
    
    protected Module mModule;
    protected FunctionType mFunctionType;
    protected LLVMValueRef mValue;
    protected string mName;
}


// I hope it's obvious that the following are stub functions.

Type astTypeToBackendType(ast.Type, Module mod)
{
    return new Int32Type(mod);
}

Value astTypeToBackendValue(ast.Type, Module mod)
{
    return new Int32Value(mod);
}
