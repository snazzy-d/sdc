/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.value;

import std.string;

import llvm.c.Core;
import llvm.Ext;

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
    
    /*
     * This is not related to the attributes 'const' or 'immutable'.
     * This boolean and the following union are all in aid of constant
     * folding. If constant is true, then this Value has been constructed
     * out of all compile time known values, thus this value is known at 
     * compile time. This will be used in places like assert, static 
     * arrays, bounds checked type conversions -- places in the D spec 
     * where constant folding is required.
     */
    bool constant;
    union
    {
        bool constBool;
        int constInt;
        long constLong;
        double constDouble;
    }
    
    Type type() @property
    {
        return mType;
    }
    
    void type(Type t) @property
    {
        mType = t;
    }
    
    void performCastInPlace(Type t)
    {
        panic(location, "invalid cast");
    }
    
    Value performCast(Type t)
    {
        panic(location, "invalid cast");
        assert(false);
    }
            
    Value importToModule(Module m);
    
    LLVMValueRef get();
    void set(Value val);
    void set(LLVMValueRef val);
    Value add(Value val);
    Value sub(Value val);
    Value mul(Value val);
    Value div(Value val);
    Value eq(Value val);
    Value neq(Value val);
    Value gt(Value val);
    Value lte(Value val);
    
    Value or(Value val)
    {
        auto v = LLVMBuildOr(mModule.builder, this.get(), val.get(), "or");
        auto b = new BoolValue(mModule, location);
        b.set(v);
        return b;
    }
    
    Value call(Value[] args);
    Value init(Location location);
    Value getMember(string name);

    
    protected Module mModule;
    protected Type mType;
    protected LLVMValueRef mValue;
}

mixin template InvalidOperation(alias FunctionSignature)
{
    mixin("override " ~ FunctionSignature ~ " {"
          `    panic(location, "invalid operation used."); assert(false); }`);
}

mixin template LLVMIntComparison(alias ComparisonType, alias ComparisonString)
{
    mixin("override Value " ~ ComparisonString ~ "(Value val) {" ~
        "auto v = LLVMBuildICmp(mModule.builder, ComparisonType, get(), val.get(), toStringz(ComparisonString));"
        "auto b = new BoolValue(mModule, location);"
        "b.set(v);"
        "return b;"
    "}");
}


class PrimitiveIntegerValue(T, B, alias C) : Value
{
    this(Module mod, Location loc)
    { 
        super(mod, loc);
        mType = new B(mod);
        mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "int");
    }
    
    this(Module mod, Location loc, T n)
    {
        this(mod, loc);
        constInit(n);
    }
    
    this(Module mod, Value val)
    {
        this(mod, val.location);
        set(val);
    }
    
    override Value importToModule(Module m)
    {
        panic(location, "tried to import primitive integer value across modules.");
        assert(false);
    }
    
    override void performCastInPlace(Type t)
    {
        auto v = LLVMBuildIntCast(mModule.builder, get(), t.llvmType, "cast");
        mValue = LLVMBuildAlloca(mModule.builder, LLVMTypeOf(v), "castalloca");
        LLVMBuildStore(mModule.builder, v, mValue);
        mType = t;
    }
    
    override Value performCast(Type t)
    {
        auto v = t.getValue(location);
        v.set(LLVMBuildIntCast(mModule.builder, get(), t.llvmType, "cast"));
        return v;
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "primitive");
    }
    
    override void set(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            mixin(C ~ " = val." ~ C ~ ";");
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
    }
    
    override void set(LLVMValueRef val)
    {
        constant = false;
        LLVMBuildStore(mModule.builder, val, mValue);
    }
    
    override Value add(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            mixin(C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " + val." ~ C ~ ");");
        }
        auto result = LLVMBuildAdd(mModule.builder, this.get(), val.get(), "add");
        auto v = new typeof(this)(mModule, location);
        v.set(result);
        return v;
    }
    
    override Value sub(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            mixin(C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " - val." ~ C ~ ");");
        }
        auto result = LLVMBuildSub(mModule.builder, this.get(), val.get(), "add");
        auto v = new typeof(this)(mModule, location);
        v.set(result);
        return v;
    }
    
    override Value mul(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            mixin(C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " * val." ~ C ~ ");");
        }
        auto result = LLVMBuildMul(mModule.builder, this.get(), val.get(), "add");
        auto v = new typeof(this)(mModule, location);
        v.set(result);
        return v;
    }
    
    override Value div(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            mixin(C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " / val." ~ C ~ ");");
        }
        auto result = LLVMBuildSDiv(mModule.builder, this.get(), val.get(), "add");
        auto v = new typeof(this)(mModule, location);
        v.set(result);
        return v;
    }
    
    mixin LLVMIntComparison!(LLVMIntPredicate.EQ, "eq");
    mixin LLVMIntComparison!(LLVMIntPredicate.NE, "neq");
    mixin LLVMIntComparison!(LLVMIntPredicate.SGT, "gt");
    mixin LLVMIntComparison!(LLVMIntPredicate.SLE, "lte");
    
    mixin InvalidOperation!"Value call(Value[])";
    mixin InvalidOperation!"Value getMember(string)";
    
    override Value init(Location location)
    {
        return new typeof(this)(mModule, location, 0);
    }
    
    protected void constInit(T n)
    {
        auto val = LLVMConstInt(mType.llvmType(), n, false);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
        mixin(C ~ " = n;");
    }
}

alias PrimitiveIntegerValue!(bool, BoolType, "constBool") BoolValue;
alias PrimitiveIntegerValue!(int, IntType, "constInt") IntValue;
alias PrimitiveIntegerValue!(long, LongType, "constLong") LongValue;

class DoubleValue : Value
{
    this(Module mod, Location location)
    {
        super(mod, location);
        mType = new DoubleType(mod);
        mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "double");
    }
    
    this(Module mod, Location location, double d)
    {
        this(mod, location);
        constInit(d);
    }
    
    override Value importToModule(Module mod)
    {
        panic("attempted to import double value across modules.");
        assert(false);
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "doubleget");
    }
    
    override void set(Value val)
    {
        this.constant = this.constant && val.constant;
        if (this.constant) {
            this.constDouble = val.constDouble;
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
    }
    
    override void set(LLVMValueRef val)
    {
        constant = false;
        LLVMBuildStore(mModule.builder, val, mValue);
    }
    
    override Value add(Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFAdd(mModule.builder, this.get(), val.get(), "fadd");
        v.set(result);
        v.constant = this.constant && val.constant;
        if (v.constant) {
            v.constDouble = this.constDouble + val.constDouble;
        }
        return v;
    }
    
    override Value sub(Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFSub(mModule.builder, this.get(), val.get(), "fsub");
        v.set(result);
        v.constant = this.constant && val.constant;
        if (v.constant) {
            v.constDouble = this.constDouble - val.constDouble;
        }
        return v;
    }
    
    override Value mul(Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFMul(mModule.builder, this.get(), val.get(), "fmul");
        v.set(result);
        v.constant = this.constant && val.constant;
        if (v.constant) {
            v.constDouble = this.constDouble * val.constDouble;
        }
        return v;
    }
    
    override Value div(Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFDiv(mModule.builder, this.get(), val.get(), "fdiv");
        v.set(result);
        v.constant = this.constant && val.constant;
        if (v.constant) {
            v.constDouble = this.constDouble / val.constDouble;
        }
        return v;
    }
    
    override Value init(Location location)
    {
        return new DoubleValue(mModule, location);
    }
    
    mixin InvalidOperation!"Value eq(Value)";
    mixin InvalidOperation!"Value neq(Value)";
    mixin InvalidOperation!"Value gt(Value)";
    mixin InvalidOperation!"Value lte(Value)";
    mixin InvalidOperation!"Value call(Value[])";
    mixin InvalidOperation!"Value getMember(string)";
    
    protected void constInit(double d)
    {
        auto val = LLVMConstReal(mType.llvmType, d);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
        constDouble = d;
    }
}

class FunctionValue : Value
{
    string name;
    
    this(Module mod, Location location, FunctionType func, string name)
    {
        super(mod, location);
        this.name = name;
        mType = func;
        mValue = LLVMAddFunction(mod.mod, toStringz(name), func.llvmType);
    }
    
    override Value importToModule(Module m)
    {
        auto newType = cast(FunctionType) mType.importToModule(m);
        assert(newType);
        return new FunctionValue(m, location, newType, name);
    }
    
    override LLVMValueRef get()
    {
        return mValue;
    }
    
    override Value call(Value[] args)
    {
        // Check call with function signature.
        auto functionType = cast(FunctionType) mType;
        assert(functionType);
        if (functionType.argumentTypes.length != args.length) {
            goto err;
        }
        foreach (i, arg; functionType.argumentTypes) {
            if (arg != args[i].type) {
                goto err;
            }
        }
        
        LLVMValueRef[] llvmArgs;
        foreach (arg; args) {
            llvmArgs ~= arg.get();
        }
        
        auto retval = LLVMBuildCall(mModule.builder, mValue, llvmArgs.ptr, llvmArgs.length, "call");
        auto val = functionType.returnType.getValue(location);
        val.set(retval);
        return val;
        
    err:
        error(location, "can't call function with given arguments.");
        assert(false);
    }
    
    mixin InvalidOperation!"void set(Value)";
    mixin InvalidOperation!"void set(LLVMValueRef)";
    mixin InvalidOperation!"Value add(Value)";
    mixin InvalidOperation!"Value sub(Value)";
    mixin InvalidOperation!"Value mul(Value)";
    mixin InvalidOperation!"Value div(Value)";
    mixin InvalidOperation!"Value eq(Value)";
    mixin InvalidOperation!"Value neq(Value)";
    mixin InvalidOperation!"Value gt(Value)";
    mixin InvalidOperation!"Value lte(Value)";
    mixin InvalidOperation!"Value or(Value)";
    mixin InvalidOperation!"Value getMember(string)";
    
    override Value init(Location location)
    {
        panic(location, "tried to get the init of a function value.");
        assert(false);
    }
}


class StructValue : Value
{
    this(Module mod, Location location, StructType type)
    {
        super(mod, location);
        mType = type;
        mValue = LLVMBuildAlloca(mod.builder, type.llvmType, "struct");
    }
    
    override Value importToModule(Module m)
    {
        auto newType = cast(StructType) mType.importToModule(m);
        assert(newType);
        return new StructValue(m, location, newType);
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "struct");
    }
    
    override Value init(Location location)
    {
        panic(location, "tried to get the init of a struct value.");
        assert(false);
    }
    
    override Value getMember(string name)
    {
        auto t = new IntType(mModule);
        LLVMValueRef[] indices;
        indices ~= LLVMConstInt(t.llvmType, 0, false);
        
        auto asStruct = cast(StructType) mType;
        assert(asStruct);
        indices ~= LLVMConstInt(t.llvmType, asStruct.memberPositions[name], false);
        
        auto i = new IntValue(mModule, location);
        i.mValue = LLVMBuildGEP(mModule.builder, mValue, indices.ptr, indices.length, "gep");
        return i;
    }
    
    mixin InvalidOperation!"void set(Value)";
    mixin InvalidOperation!"void set(LLVMValueRef)";
    mixin InvalidOperation!"Value add(Value)";
    mixin InvalidOperation!"Value sub(Value)";
    mixin InvalidOperation!"Value mul(Value)";
    mixin InvalidOperation!"Value div(Value)";
    mixin InvalidOperation!"Value eq(Value)";
    mixin InvalidOperation!"Value neq(Value)";
    mixin InvalidOperation!"Value gt(Value)";
    mixin InvalidOperation!"Value lte(Value)";
    mixin InvalidOperation!"Value or(Value)";
    mixin InvalidOperation!"Value call(Value[])";
}

enum OnFailure
{
    DieWithError,
    ReturnNull,
}

Type astTypeToBackendType(ast.Type type, Module mod, OnFailure onFailure)
{
    switch (type.type) {
    case ast.TypeType.Primitive:
        return primitiveTypeToBackendType(cast(ast.PrimitiveType) type.node, mod, onFailure);
    case ast.TypeType.UserDefined:
        return userDefinedTypeToBackendType(cast(ast.UserDefinedType) type.node, mod, onFailure);
    default:
        panic(type.location, "unhandled type type.");
    }
    
    assert(false);
}

Type primitiveTypeToBackendType(ast.PrimitiveType type, Module mod, OnFailure onFailure)
{
    switch (type.type) {
    case ast.PrimitiveTypeType.Bool:
        return new BoolType(mod);
    case ast.PrimitiveTypeType.Int:
        return new IntType(mod);
    case ast.PrimitiveTypeType.Long:
        return new LongType(mod);
    case ast.PrimitiveTypeType.Double:
        return new DoubleType(mod);
    default:
        panic(type.location, "unhandled primitive type type.");
    }
    
    assert(false);
}

Type userDefinedTypeToBackendType(ast.UserDefinedType type, Module mod, OnFailure onFailure)
{
    auto name = extractQualifiedName(type.qualifiedName);
    auto store = mod.search(name);
    if (store is null) {
        if (onFailure == OnFailure.ReturnNull) {
            return null;
        } else {
            error(type.location, format("undefined type '%s'.", name));
        }
    }
    if (store.storeType != StoreType.Type) {
        if (onFailure == OnFailure.ReturnNull) {
            return null;
        } else {
            error(type.location, format("'%s' is not valid type."));
        }
    }
    return store.type;
}
