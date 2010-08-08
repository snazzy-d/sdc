/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.value;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.location;
import sdc.extract.base;
import sdc.gen.sdcmodule;
import sdc.gen.type;


abstract class Value
{
    /// The location that this Value was created at.
    Location location;
    
    this(Module mod, Location loc)
    {
        mModule = mod;
        location = loc;
    }
    
    bool constant;
    union
    {
        int constInt;
    }
    
    Type type();
    LLVMValueRef get();
    void set(Value val);
    void add(Value val);
    Value init(Location location);
    
    protected Module mModule;
    protected Type mType;
    protected LLVMValueRef mValue;
}

class IntValue : Value
{
    this(Module mod, Location loc)
    {
        super(mod, loc);
        mType = new IntType(mod);
        mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "int");
    }
        
    this(Module mod, ast.IntegerLiteral integerLiteral)
    {
        this(mod, integerLiteral.location);
        constInt = extractIntegerLiteral(integerLiteral);
        constInit(constInt);
    }
    
    this(Module mod, Location location, int constInitialiser)
    {
        this(mod, location);
        constInit(constInitialiser);
    }
    
    this(Module mod, Value val)
    {
        this(mod, val.location);
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
    
    override Value init(Location location)
    {
        return new IntValue(mModule, location, 0);
    }
    
    protected void constInit(int n)
    {
        auto val = LLVMConstInt(mType.llvmType(), n, false);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
    }
}


class FunctionValue : Value
{
    this(Module mod, Location location, FunctionType func, string name)
    {
        super(mod, location);
        mType = func;
        mName = name;
        mValue = LLVMAddFunction(mod.mod, toStringz(name), func.llvmType);
    }
    
    override Type type()
    {
        return mType;
    }
    
    override LLVMValueRef get()
    {
        return mValue;
    }
    
    override void set(Value val)
    {
        panic(val.location, "tried to directly set a function value.");
    }
    
    override void add(Value val)
    {
        panic(val.location, "tried to add a value directly to a function value.");
    }
    
    override Value init(Location location)
    {
        panic(location, "tried to get the init of a function value.");
        assert(false);
    }
    
    protected string mName;
}


// I hope it's obvious that the following are stub functions.

Type astTypeToBackendType(ast.Type, Module mod)
{
    return new IntType(mod);
}

Value astTypeToBackendValue(ast.Type type, Module mod)
{
    return new IntValue(mod, type.location);
}
