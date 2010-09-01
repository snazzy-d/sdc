/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import std.string;

import llvm.c.Core;

import sdc.compilererror;
import sdc.location;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;


enum DType
{
    None,
    Bool,
    Int,
    Long,
    Double,
    Complex,
    Function,
    Struct,
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
    
    Type importToModule(Module mod);
    
    /// An opEquals appropriate for simple types.
    override bool opEquals(Object o)
    {
        auto asType = cast(Type) o;
        if (!asType) return false;
        
        return this.mType == asType.mType;
    }
    
    Value getValue(Location location);
    
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
    
    override BoolType importToModule(Module mod)
    {
        return new BoolType(mod);
    }
    
    override Value getValue(Location location) { return new BoolValue(mModule, location); }
}

class IntType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Int;
        mType = LLVMInt32TypeInContext(mod.context);
    }
    
    override IntType importToModule(Module mod)
    {
        return new IntType(mod);
    }
    
    override Value getValue(Location location) { return new IntValue(mModule, location); }
}

class LongType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Long;
        mType = LLVMInt64TypeInContext(mod.context);
    }
    
    override LongType importToModule(Module mod)
    {
        return new LongType(mod);
    }
    
    override Value getValue(Location location) { return new LongValue(mModule, location); }
}

class DoubleType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Double;
        mType = LLVMDoubleTypeInContext(mod.context);
    }
    
    override DoubleType importToModule(Module mod)
    {
        return new DoubleType(mod);
    }
    
    override Value getValue(Location location)
    {
        return new DoubleValue(mModule, location);
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
        returnType = astTypeToBackendType(mFunctionDeclaration.retval, mModule, OnFailure.DieWithError);
        LLVMTypeRef[] params;
        foreach (param; mFunctionDeclaration.parameters) {
            auto type = astTypeToBackendType(param.type, mModule, OnFailure.DieWithError);
            argumentTypes ~= type;
            params ~= type.llvmType;
        }
        mType = LLVMFunctionType(returnType.llvmType, params.ptr, params.length, false);
    }
    
    override FunctionType importToModule(Module mod)
    {
        auto f = new FunctionType(mod, mFunctionDeclaration);
        f.declare();
        return f;
    }
    
    override Value getValue(Location location) { return null; }

    protected ast.FunctionDeclaration mFunctionDeclaration;
}

class StructType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Struct;
    }
    
    void declare()
    {
        LLVMTypeRef[] types;
        foreach (member; members) {
            types ~= member.llvmType;
        }
        mType = LLVMStructTypeInContext(mModule.context, types.ptr, types.length, false);
    }
    
    override Value getValue(Location location)
    {
        return new StructValue(mModule, location, this);
    }
    
    override StructType importToModule(Module mod)
    {
        auto s = new StructType(mod);
        s.declare();
        return s;
    }
    
    void addMemberVar(string id, Type t)
    {
        memberPositions[id] = members.length;
        members ~= t;
    }
    
    Type[] members;
    int[string] memberPositions;
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
}
