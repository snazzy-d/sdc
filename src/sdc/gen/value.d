/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.value;

import std.algorithm;
import std.conv;
import std.exception;
import std.string;

import llvm.c.Core;
import llvm.Ext;

import sdc.util;
import sdc.mangle;
import sdc.compilererror;
import sdc.location;
import sdc.global;
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
        uint constUint;
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
    
    Value performCast(Type t)
    {
        panic(location, "invalid cast");
        assert(false);
    }
    
    void fail(string s = "unspecified") { panic(location, "call to unimplemented method '" ~ s ~ "'."); }
        
    LLVMValueRef get() { fail("get"); assert(false); }
    void set(Value val) { fail("set:Value"); assert(false); }
    void set(LLVMValueRef val) { fail("set:LLVMValueRef"); assert(false); }
    Value add(Value val) { fail("add"); assert(false); }
    Value sub(Value val) { fail("sub"); assert(false); }
    Value mul(Value val) { fail("mul"); assert(false); }
    Value div(Value val) { fail("div"); assert(false); }
    Value eq(Value val) { fail("eq"); assert(false); }
    Value neq(Value val) { fail("neq"); assert(false); }
    Value gt(Value val) { fail("gt"); assert(false); }
    Value lte(Value val) { fail("lte"); assert(false); }
    Value dereference() { fail("dereference"); assert(false); }
    Value index(Value val) { fail("index"); assert(false); }
    
    Value addressOf()
    {
        auto v = new PointerValue(mModule, location, mType);
        v.set(mValue);
        return v;
    }
    
    Value or(Value val)
    {
        auto v = LLVMBuildOr(mModule.builder, this.get(), val.get(), "or");
        auto b = new BoolValue(mModule, location);
        b.set(v);
        return b;
    }
    
    Value call(Value[] args) { fail("call"); assert(false); }
    Value init(Location location) { fail("init"); assert(false); }
    Value getMember(string name) { fail("getMember"); assert(false); }
    Module getModule() { return mModule; }
    
    Value importToModule(Module mod)
    {
        return this;
    }
    
    protected Module mModule;
    protected Type mType;
    package LLVMValueRef mValue;
}

class VoidValue : Value
{
    this(Module mod, Location loc)
    {
        super(mod, loc);
        mType = new VoidType(mod);
    }
    
    override void fail(string s)
    {
        error(location, "can't perform an action on variable of type 'void'.");
    }
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


class PrimitiveIntegerValue(T, B, alias C, bool SIGNED) : Value
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
    
    override Value performCast(Type t)
    {
        auto v = t.getValue(mModule, location);
        if (isIntegerDType(t.dtype)) {
            if (mType.dtype < t.dtype) {
                v.set(LLVMBuildZExt(mModule.builder, get(), t.llvmType, "cast"));
            } else if (mType.dtype > t.dtype) {
                v.set(LLVMBuildTrunc(mModule.builder, get(), t.llvmType, "cast"));
            } else {
                v.set(get());
            }
        } else if (isFPDtype(t.dtype)) {
            v.set(LLVMBuildUIToFP(mModule.builder, get(), t.llvmType, "cast"));
        } else {
            panic(location, "invalid cast");
        }
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
        static if (SIGNED) {
            auto result = LLVMBuildSDiv(mModule.builder, this.get(), val.get(), "add");
        } else {
            auto result = LLVMBuildUDiv(mModule.builder, this.get(), val.get(), "add");
        }
        auto v = new typeof(this)(mModule, location);
        v.set(result);
        return v;
    }
    
    mixin LLVMIntComparison!(LLVMIntPredicate.EQ, "eq");
    mixin LLVMIntComparison!(LLVMIntPredicate.NE, "neq");
    static if (SIGNED) {
        mixin LLVMIntComparison!(LLVMIntPredicate.SGT, "gt");
        mixin LLVMIntComparison!(LLVMIntPredicate.SLE, "lte");
    } else {
        mixin LLVMIntComparison!(LLVMIntPredicate.UGT, "gt");
        mixin LLVMIntComparison!(LLVMIntPredicate.ULE, "lte");
    }
    
    
    override Value init(Location location)
    {
        return new typeof(this)(mModule, location, 0);
    }
    
    protected void constInit(T n)
    {
        auto val = LLVMConstInt(mType.llvmType(), n, !SIGNED);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
        mixin(C ~ " = n;");
    }
}

alias PrimitiveIntegerValue!(bool, BoolType, "constBool", true) BoolValue;
alias PrimitiveIntegerValue!(int, IntType, "constInt", true) IntValue;
alias PrimitiveIntegerValue!(uint, UintType, "constUint", false) UintValue;
alias PrimitiveIntegerValue!(long, LongType, "constLong", true) LongValue;

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
    
    override Value performCast(Type t)
    {
        auto v = t.getValue(mModule, location);
        if (isIntegerDType(t.dtype)) {
            v.set(LLVMBuildFPToSI(mModule.builder, get(), t.llvmType, "cast"));
        } else if (isFPDtype(t.dtype)) {
            panic(location, "floating point to floating point casts are unimplemented.");
        } else {
            panic(location, "invalid cast.");
        }
        return v;
    }
    
    version (none) override Value importToModule(Module mod)
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
    
    override Value addressOf()
    {
        auto v = new PointerValue(mModule, location, mType);
        v.set(mValue);
        return v;
    }

    override Value init(Location location)
    {
        return new DoubleValue(mModule, location);
    }
    
    protected void constInit(double d)
    {
        auto val = LLVMConstReal(mType.llvmType, d);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
        constDouble = d;
    }
}

class ArrayValue : PointerValue
{
    this(Module mod, Location location, Type base)
    {
        auto asArray = new ArrayType(mod, base);
        super(mod, location, asArray.structType);
        mType = asArray;
    }
    
    override Value init(Location location)
    {
        auto asArray = cast(ArrayType) mType;
        auto l = new LongValue(mModule, location);
        l.set(LLVMSizeOf(asArray.structType.llvmType));
        auto ll = [l];
        panic(location, "arrays are unimplemented.");
        assert(false);
        // Allocate memory here,
        // then cast to asArray.structTypePointer.
        // return that.
    }
}

class PointerValue : Value
{
    Type baseType;
    
    this(Module mod, Location location, Type baseType)
    {
        super(mod, location);
        this.baseType = baseType;
        mType = new PointerType(mod, baseType);
        mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "pv");
    }
    
    override Value performCast(Type t)
    {
        auto v = t.getValue(mModule, location);
        if (t.dtype == DType.Pointer) {
            v.set(LLVMBuildPointerCast(mModule.builder, get(), t.llvmType(), "pcast"));
        } else {
            error(location, "cannot cast from pointer to non-pointer type.");
        }
        return v;
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "get");
    }
    
    override void set(Value val)
    {
        if (val.type.dtype == DType.NullPointer) {
            set(init(location));
        } else {
            LLVMBuildStore(mModule.builder, val.get(), mValue);
        }
    }
    
    override void set(LLVMValueRef val)
    {
        LLVMBuildStore(mModule.builder, val, mValue);
    }
    
    override Value dereference()
    {
        auto t = new IntType(mModule);
        LLVMValueRef[] indices;
        indices ~= LLVMConstInt(t.llvmType, 0, false);
        
        auto v = baseType.getValue(mModule, location);
        v.mValue = LLVMBuildGEP(mModule.builder, get(), indices.ptr, indices.length, "gep");
        return v;
    }
    
    override Value index(Value val)
    {
        val = implicitCast(val, new IntType(mModule));
        LLVMValueRef[] indices;
        indices ~= val.get();
        
        auto v = baseType.getValue(mModule, location);
        v.mValue = LLVMBuildGEP(mModule.builder, get(), indices.ptr, indices.length, "gep");
        return v;
    }
    
    override Value init(Location location)
    {
        auto v = new PointerValue(mModule, location, baseType);
        v.set(LLVMConstNull(v.mType.llvmType));
        return v;
    }
    
    override Value getMember(string name)
    {
        auto v = dereference();
        return v.getMember(name);
    }
}

class NullPointerValue : PointerValue
{
    this(Module mod, Location location)
    {
        super(mod, location, new VoidType(mod));
        mType = new NullPointerType(mod);
    }
}

class FunctionValue : Value
{
    string name;
    string mangledName;
    
    this(Module mod, Location location, FunctionType func, string name, string forceMangled="")
    {
        super(mod, location);
        this.name = name;
        mType = func;
        if (mod.currentLinkage == ast.Linkage.ExternD) {
            if (forceMangled == "") {
                mangledName = mangle(func);
            } else {
                mangledName = forceMangled;
            }
        } else {
            mangledName = name;
        }
        mValue = LLVMAddFunction(mod.mod, toStringz(mangledName), func.llvmType);
    }
    
    protected string mangle(FunctionType type)
    {
        if (name == "main") {
            // TMP
            return "main";
        }
        auto s = startMangle();
        if (type.parentAggregate !is null) {
            mangleQualifiedName(s, type.parentAggregate.name);
        } else {
            if (mModule.name is null) {
                panic("null module name.");
            }
            mangleQualifiedName(s, mModule.name);
        }
        mangleLName(s, name);
        if (type.parentAggregate !is null) {
            s ~= "M";
        }
        mangleFunction(s, type);
        return s;
    }
    
    Value newWithAddedArgument(Type newArgument, string argName)
    {
        auto asFunctionType = cast(FunctionType) mType;
        assert(asFunctionType);
        auto returnType = asFunctionType.returnType;
        auto args = asFunctionType.argumentTypes;
        auto argNames = asFunctionType.argumentNames;
        args ~= newArgument;
        argNames ~= argName;
        auto t = new FunctionType(mModule, returnType, args, argNames);
        t.linkage = asFunctionType.linkage;
        t.parentAggregate = asFunctionType.parentAggregate;
        t.declare();
        LLVMDeleteFunction(mValue);
        return new FunctionValue(mModule, location, t, name, mangle(asFunctionType));
    }
    
    override LLVMValueRef get()
    {
        return mValue;
    }
    
    override Value call(Value[] args)
    {
        void failure()
        {
            error(location, "can't call function with given arguments.");
        }
            
        // Check call with function signature.
        auto functionType = cast(FunctionType) mType;
        assert(functionType);
        if (functionType.argumentTypes.length != args.length) {
            failure();
        }
        foreach (i, arg; functionType.argumentTypes) {
            args[i] = implicitCast(args[i], arg);
            if (arg != args[i].type) {
                failure();
            }
        }
        
        LLVMValueRef[] llvmArgs;
        foreach (arg; args) {
            llvmArgs ~= arg.get();
        }
        
        Value val;
        if (functionType.returnType.dtype != DType.Void) {
            auto retval = LLVMBuildCall(mModule.builder, mValue, llvmArgs.ptr, llvmArgs.length, "call");
            val = functionType.returnType.getValue(mModule, location);
            val.set(retval);
        } else {
            LLVMBuildCall(mModule.builder, mValue, llvmArgs.ptr, llvmArgs.length, "");
            val = new VoidValue(mModule, location);
        }
        return val;
    }
    
    override Value init(Location location)
    {
        panic(location, "tried to get the init of a function value.");
        assert(false);
    }
    
    override Value importToModule(Module mod)
    {
        auto f = new FunctionValue(mod, location, enforce(cast(FunctionType) mType.importToModule(mod)), name, mangledName);
        return f;
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
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "struct");
    }
    
    override void set(Value val)
    {
        LLVMBuildStore(mModule.builder, val.get(), mValue);
    }
    
    override void set(LLVMValueRef val)
    {
        LLVMBuildStore(mModule.builder, val, mValue);
    }
    
    override Value init(Location location)
    {
        panic(location, "tried to get the init of a struct value.");
        assert(false);
    }
    
    override Value getMember(string name)
    {
        auto asStruct = cast(StructType) mType;
        assert(asStruct);
        
        if (auto p = name in asStruct.memberFunctions) {
            return *p;
        }
        
        auto t = new IntType(mModule);
        LLVMValueRef[] indices;
        indices ~= LLVMConstInt(t.llvmType, 0, false);
        

        auto index = asStruct.memberPositions[name];
        indices ~= LLVMConstInt(t.llvmType, index, false);
        
        auto i = asStruct.members[index].getValue(mModule, location);
        i.mValue = LLVMBuildGEP(mModule.builder, mValue, indices.ptr, indices.length, "gep");
        return i;
    }
}

class ScopeValue : Value
{
    Scope _scope;
    
    this(Module mod, Location location, Scope _scope)
    {
        super(mod, location);
        this._scope = _scope;
    }
    
    override Value getMember(string name)
    {
        auto store = _scope.get(name);
        if (store.storeType == StoreType.Scope) {
            return new ScopeValue(mModule, location, store.getScope());
        }
        return _scope.get(name).value;
    }
}

enum OnFailure
{
    DieWithError,
    ReturnNull,
}

Type astTypeToBackendType(ast.Type type, Module mod, OnFailure onFailure)
{
    Type t;
    switch (type.type) {
    case ast.TypeType.Primitive:
        t = primitiveTypeToBackendType(cast(ast.PrimitiveType) type.node, mod, onFailure);
        break;
    case ast.TypeType.UserDefined:
        t = userDefinedTypeToBackendType(cast(ast.UserDefinedType) type.node, mod, onFailure);
        break;
    case ast.TypeType.Inferred:
        t = new InferredType(mod);
        break;
    default:
        panic(type.location, "unhandled type type.");
    }
    
    if (t is null) {
        return null;
    }        
    
    for (int i = type.suffixes.length - 1; i >= 0; i--) {
        auto suffix = type.suffixes[i];
        if (suffix.type == ast.TypeSuffixType.Pointer) {
            t = new PointerType(mod, t);
        } else if (suffix.type == ast.TypeSuffixType.DynamicArray) {
            t = new ArrayType(mod, t);
        } else {
            panic(type.location, "unimplemented type suffix.");
        }
    }
    
    return t;
}

Type primitiveTypeToBackendType(ast.PrimitiveType type, Module mod, OnFailure onFailure)
{
    switch (type.type) {
    case ast.PrimitiveTypeType.Void:
        return new VoidType(mod);
    case ast.PrimitiveTypeType.Bool:
        return new BoolType(mod);
    case ast.PrimitiveTypeType.Int:
        return new IntType(mod);
    case ast.PrimitiveTypeType.Uint:
        return new UintType(mod);
    case ast.PrimitiveTypeType.Long:
        return new LongType(mod);
    case ast.PrimitiveTypeType.Double:
        return new DoubleType(mod);
    default:
        panic(type.location, format("unhandled primitive type '%s'.", to!string(type.type)));
    }
    
    assert(false);
}

Type userDefinedTypeToBackendType(ast.UserDefinedType type, Module mod, OnFailure onFailure)
{
    auto name = extractQualifiedName(type.qualifiedName);
    Scope baseScope;
    foreach (identifier; type.qualifiedName.identifiers) {
        Store store;
        if (baseScope !is null) {
            store = baseScope.get(extractIdentifier(identifier));
        } else {
            store = mod.search(extractIdentifier(identifier));
        }
        
        if (store is null) {
            if (onFailure == OnFailure.DieWithError) {
                error(type.location, format("undefined type '%s'.", name));
            } else {
                errorMessageOnly(type.location, format("undefined type '%s' (temporary message, compilation continues -- you will get error spam).", name));
                return null;
            }
        } else if (store.storeType == StoreType.Value) {
            error(type.location, format("'%s' is not a type.", name));
        } else if (store.storeType == StoreType.Type) {
            return store.type;
        } else if (store.storeType == StoreType.Scope) {
            baseScope = store.getScope();
        }
    }
    assert(false);
}

void binaryOperatorImplicitCast(Value* lhs, Value* rhs)
{    
    if (lhs.type.dtype == rhs.type.dtype) {
        return;
    }
 
    auto toDType = max(lhs.type.dtype, rhs.type.dtype);
    auto t = dtypeToType(toDType, lhs.getModule());
    if (lhs.type.dtype > rhs.type.dtype) {
        *rhs = implicitCast(*rhs, t);
    } else {
        *lhs = implicitCast(*lhs, t);
    }
}

Value implicitCast(Value v, Type toType)
{
    if (v.type.dtype == DType.NullPointer && toType.dtype == DType.Pointer) {
        return v;
    }
    if (isComplexDType(v.type.dtype)) {
        if (v.type == toType) {
            return v;
        }
        panic(v.location, "casts involving complex types are unimplemented.");
    }
    if (toType.dtype == v.type.dtype && toType.dtype != DType.Pointer) {
        return v;
    }
    if (!canImplicitCast(v.type.dtype, toType.dtype)) {
        // TODO: Implement toString for Types.
        error(v.location, format("cannot implicitly cast '%s' to '%s'.", to!string(v.type.dtype), to!string(toType.dtype)));
    }
    return v.performCast(toType);
}

bool canImplicitCast(DType from, DType to)
{
    switch (from) with (DType) {
    case Bool:
        return true;
    case Char:
    case Ubyte:
    case Byte:
        return to >= Char;
    case Wchar:
    case Ushort:
    case Short:
        return to >= Wchar;
    case Dchar:
    case Uint:
    case Int:
        return to >= Dchar;
    case Ulong:
    case Long:
        return to >= Ulong;
    case Float:
    case Double:
    case Real:
        return to >= Float;
    case Pointer:
    case NullPointer:
        return to == Pointer || to == NullPointer; 
    default:
        return false;
    }
    assert(false);
}
