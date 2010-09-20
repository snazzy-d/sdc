/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.type;

import std.string;

import llvm.c.Core;

import sdc.util;
import sdc.compilererror;
import sdc.location;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.value;


enum DType
{
    None,
    Void,
    Bool,
    Char,
    Ubyte,
    Byte,
    Wchar,
    Ushort,
    Short,
    Dchar,
    Uint,
    Int,
    Ulong,
    Long,
    Float,
    Double,
    Real,
    Pointer,
    Array,
    Complex,
    Function,
    Struct,
    Inferred,
}

Type dtypeToType(DType dtype, Module mod)
{
    final switch (dtype) with (DType) {
    case None:
        break;
    case Void:
        return new VoidType(mod);
    case Bool:
        return new BoolType(mod);
    case Char:
    case Ubyte:
    case Byte:
    case Wchar:
    case Ushort:
    case Short:
    case Dchar:
    case Uint:
        break;
    case Int:
        return new IntType(mod);
    case Ulong:
        break;
    case Long:
        return new LongType(mod); 
    case Float:
        break;
    case Double:
        return new DoubleType(mod);
    case Real:
    case Pointer:
    case Array:
    case Complex:
    case Function:
    case Struct:
        break;
    case Inferred:
        return new InferredType(mod);
    }
    panic("tried to get Type out of invalid DType.");
    assert(false);
}

pure bool isComplexDType(DType dtype)
{
    return dtype >= DType.Complex;
}

pure bool isIntegerDType(DType dtype)
{
    return dtype >= DType.Bool && dtype <= DType.Long;
}

pure bool isFPDtype(DType dtype)
{
    return dtype >= DType.Float && dtype <= DType.Double;
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

class VoidType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Void;
        mType = LLVMVoidTypeInContext(mod.context);
    }
    
    override VoidType importToModule(Module mod)
    {
        return new VoidType(mod);
    }
    
    override Value getValue(Location location)
    {
        return new VoidValue(mModule, location);
    }
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

class PointerType : Type
{
    Type base;
    
    this(Module mod, Type base)
    {
        super(mod);
        this.base = base;
        dtype = DType.Pointer;
        if (base.dtype == DType.Void) {
            // Handle void pointers special like.
            mType = LLVMPointerType(LLVMInt8TypeInContext(mod.context), 0);
        } else {
            mType = LLVMPointerType(base.llvmType, 0);
        }
    }
    
    override PointerType importToModule(Module mod)
    {
        return new PointerType(mod, base);
    }
    
    override Value getValue(Location location)
    {
        return new PointerValue(mModule, location, base);
    }
}

class ArrayType : Type
{
    Type base;
    StructType structType;
    PointerType structTypePointer;
    
    this(Module mod, Type base)
    {
        super(mod);
        this.base = base;
        dtype = DType.Array;
        structType = new StructType(mod);
        structType.addMemberVar("length", new IntType(mod));
        structType.addMemberVar("ptr", new PointerType(mod, base));
        structType.declare();
        structTypePointer = new PointerType(mod, structType);
        mType = structTypePointer.llvmType;
    }
    
    override ArrayType importToModule(Module mod)
    {
        return new ArrayType(mod, base);
    }
    
    override Value getValue(Location location)
    {
        return new ArrayValue(mModule, location, base);
    }
}

class FunctionType : Type
{
    Type returnType;
    Type[] argumentTypes;
    string[] argumentNames;
    ast.Linkage linkage;
    StructType parentAggregate;
    
    this(Module mod, ast.FunctionDeclaration functionDeclaration)
    {
        super(mod);
        linkage = mod.currentLinkage;
        dtype = DType.Function;
        returnType = astTypeToBackendType(functionDeclaration.retval, mModule, OnFailure.DieWithError);
        foreach (param; functionDeclaration.parameters) {
            argumentTypes ~= astTypeToBackendType(param.type, mModule, OnFailure.DieWithError);
            argumentNames ~= param.identifier !is null ? extractIdentifier(param.identifier) : "";
        }
    }
    
    this(Module mod, Type retval, Type[] args, string[] argNames)
    {
        super(mod);
        dtype = DType.Function;
        returnType = retval;
        argumentTypes = args;
        argumentNames = argNames;
    }
    
    void declare()
    {
        LLVMTypeRef[] params;
        foreach (t; argumentTypes) {
            params ~= t.llvmType;
        }
        mType = LLVMFunctionType(returnType.llvmType, params.ptr, params.length, false);
    }
    
    override FunctionType importToModule(Module mod)
    {
        assert(false);
    }
    
    override Value getValue(Location location) { return null; }
}

class StructType : Type
{
    ast.QualifiedName name;
    
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
    
    void addMemberFunction(string id, Value f)
    {
        memberFunctions[id] = f;
        mModule.globalScope.add(id, new Store(f));
    }
    
    Type[] members;
    int[string] memberPositions;
    Value[string] memberFunctions;
}

/* InferredType means, as soon as we get enough information
 * to know what type this is, replace InferredType with the
 * real one.
 */
class InferredType : Type
{
    this(Module mod)
    {
        super(mod);
        dtype = DType.Inferred;
    }
    
    override Type importToModule(Module mod)
    {
        return new InferredType(mod);
    }
    
    override Value getValue(Location location)
    {
        panic(location, "attempted to call InferredType.getValue");
        assert(false);
    }
}
