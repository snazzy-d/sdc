/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
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
import ast = sdc.ast.all;


abstract class Value
{
    /// The location that this Value was created at.
    Location location;
    ast.Access access;
    
    this(Module mod, Location loc)
    {
        mModule = mod;
        location = loc;
        access = mod.currentAccess;
        mGlobal = mod.currentScope is mod.globalScope;
    }
    
    bool constant;
    union
    {
        bool constBool;
        byte constByte;
        ubyte constUbyte;
        short constShort;
        ushort constUshort;
        int constInt;
        uint constUint;
        long constLong;
        ulong constUlong;
        float constFloat;
        double constDouble;
        real constReal;
        char constChar;
        wchar constWchar;
        dchar constDchar;
    }
    
    Type type() @property
    {
        return mType;
    }
    
    void type(Type t) @property
    {
        mType = t;
    }
    
    Value performCast(Location location, Type t)
    {
        throw new CompilerPanic(location, "invalid cast");
    }
    
    void fail(Location location, string s)
    { 
        throw new CompilerError(location, 
            format(`invalid operation: cannot %s value of type "%s".`, s, type.name())
        );
    }
    
    void fail(string s)
    {
        throw new CompilerPanic(format(`attempt to %s value of type "%s" failed.`, s, type.name()));
    }
        
    LLVMValueRef get() { fail("get"); assert(false); }
    void set(Value val) { fail("set (by Value)"); assert(false); }
    void set(LLVMValueRef val) { fail("set (by LLVMValueRef)"); assert(false); }
    void initialise(Value val) { set(val); }
    void initialise(LLVMValueRef val) { set(val); }
    Value add(Location loc, Value val) { fail(loc, "add"); assert(false); }
    Value inc(Location loc) { fail(loc, "increment"); assert(false); }
    Value dec(Location loc) { fail(loc, "decrement"); assert(false); }
    Value sub(Location loc, Value val) { fail(loc, "subtract"); assert(false); }
    Value mul(Location loc, Value val) { fail(loc, "multiply"); assert(false); }
    Value div(Location loc, Value val) { fail(loc, "divide"); assert(false); }
    Value eq(Location loc, Value val) { fail(loc, "compare equality of"); assert(false); }
    Value neq(Location loc, Value val) { fail(loc, "compare non-equality of"); assert(false); }
    Value gt(Location loc, Value val) { fail(loc, "compare greater-than of"); assert(false); }
    Value lte(Location loc, Value val) { fail(loc, "compare less-than of"); assert(false); }
    Value dereference(Location loc) { fail(loc, "dereference"); assert(false); }
    Value index(Location loc, Value val) { fail(loc, "index"); assert(false); }
    Value getSizeof(Location loc) { fail(loc, "getSizeof"); assert(false); }
    
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
    
    
    Value getProperty(Location loc, string name)
    {
        switch (name) {
        case "init":
            return init(loc);
        case "sizeof":
            return getSizeof(loc);
        default:
            return null;
        }
    }
    
    Value getMember(Location loc, string name)
    {
        auto prop = getProperty(loc, name);
        if (prop !is null) {
            return prop;
        }
        fail(loc, "member access on");
        assert(false);
    }
    
    Value call(Location location, Location[] argLocations, Value[] args) { fail("call"); assert(false); }
    Value init(Location location) { fail("init"); assert(false); }
    Module getModule() { return mModule; }
    
    Value importToModule(Module mod)
    {
        return this;
    }
    
    void addSetPreCallback(void delegate(Value val) callback)
    {
        mSetPreCallbacks ~= callback;
    }
    
    void addSetPostCallback(void delegate(Value val) callback)
    {
        mSetPostCallbacks ~= callback;
    }
    
    void setPreCallbacks()
    {
        foreach (callback; mSetPreCallbacks) {
            callback(this);
        }
    }
    
    void setPostCallbacks()
    {
        foreach (callback; mSetPostCallbacks) {
            callback(this);
        }
    }
    
    protected Module mModule;
    protected Type mType;
    package LLVMValueRef mValue;
    protected bool mGlobal;
    protected void delegate(Value val)[] mSetPreCallbacks;
    protected void delegate(Value val)[] mSetPostCallbacks;
}

class VoidValue : Value
{
    this(Module mod, Location loc)
    {
        super(mod, loc);
        mType = new VoidType(mod);
    }
    
    override void fail(Location location, string s)
    {
        throw new CompilerError(location, "can't perform an action on variable of type 'void'.");
    }
    
    override Value getSizeof(Location loc)
    {
        return newSizeT(mModule, loc, 1);
    }
}

mixin template LLVMIntComparison(alias ComparisonType, alias ComparisonString)
{
    mixin("override Value " ~ ComparisonString ~ "(Location location, Value val) {" ~
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
        if (mGlobal) {
            mValue = LLVMAddGlobal(mod.mod, mType.llvmType, "tlsint");
            LLVMSetThreadLocal(mValue, true);
        } else {
            mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "int");
        }
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
    
    override Value performCast(Location location, Type t)
    {
        auto v = t.getValue(mModule, location);
        if (isIntegerDType(t.dtype)) {
            if (t.dtype == DType.Bool) {
                v.set(LLVMBuildNot(mModule.builder, this.eq(location, new typeof(this)(mModule, location, 0)).get(), "boolnot"));
            } else if (mType.dtype < t.dtype) {
                v.set(LLVMBuildZExt(mModule.builder, get(), t.llvmType, "cast"));
            } else if (mType.dtype > t.dtype) {
                v.set(LLVMBuildTrunc(mModule.builder, get(), t.llvmType, "cast"));
            } else {
                v.set(get());
            }
        } else if (isFPDtype(t.dtype)) {
            v.set(LLVMBuildUIToFP(mModule.builder, get(), t.llvmType, "cast"));
        } else {
            throw new CompilerError(
                location,
                format(`cannot implicitly convert from "%s" to "%s"`,
                    type.name(),
                    t.name())
            );
        }
        return v;
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "primitive");
    }
    
    override void set(Value val)
    {
        setPreCallbacks();
        this.constant = this.constant && val.constant;
        if (this.constant) {
            mixin(C ~ " = val." ~ C ~ ";");
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
        setPostCallbacks();
    }
    
    override void set(LLVMValueRef val)
    {
        setPreCallbacks();
        constant = false;
        LLVMBuildStore(mModule.builder, val, mValue);
        setPostCallbacks();
    }
    
    override void initialise(Value val)
    {
        if (!mGlobal) {
            set(val);
        } else {
            if (!val.constant) {
                throw new CompilerError(location, "non-constant global initialiser.");
            }
            initialise(LLVMConstInt(mType.llvmType, mixin("val." ~ C), !SIGNED));
        }
    }
    
    override void initialise(LLVMValueRef val)
    {
        if (!mGlobal) {
            set(val);
        } else {
            LLVMSetInitializer(mValue, val);
        }
    }
    
    override Value add(Location location, Value val)
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
    
    override Value inc(Location location)
    {
        auto v = new typeof(this)(mModule, location);
        auto one = new typeof(this)(mModule, location, 1);
        v.set(this.add(location, one));
        return v;
    }
    
    override Value dec(Location location)
    {
        auto v = new typeof(this)(mModule, location);
        auto one = new typeof(this)(mModule, location, 1);
        v.set(this.sub(location, one));
        return v;
    }
    
    override Value sub(Location location, Value val)
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
    
    override Value mul(Location location, Value val)
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
    
    override Value div(Location location, Value val)
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
    
    override Value getSizeof(Location location)
    {
        return newSizeT(mModule, location, T.sizeof);
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
        initialise(val);
        constant = true;
        mixin(C ~ " = n;");
    }
}

alias PrimitiveIntegerValue!(bool, BoolType, "constBool", true) BoolValue;
alias PrimitiveIntegerValue!(byte, ByteType, "constByte", true) ByteValue;
alias PrimitiveIntegerValue!(ubyte, UbyteType, "constUbyte", false) UbyteValue;
alias PrimitiveIntegerValue!(short, ShortType, "constShort", true) ShortValue;
alias PrimitiveIntegerValue!(ushort, UshortType, "constUshort", false) UshortValue;
alias PrimitiveIntegerValue!(int, IntType, "constInt", true) IntValue;  
alias PrimitiveIntegerValue!(uint, UintType, "constUint", false) UintValue;
alias PrimitiveIntegerValue!(long, LongType, "constLong", true) LongValue;
alias PrimitiveIntegerValue!(ulong, UlongType, "constUlong", false) UlongValue;
alias PrimitiveIntegerValue!(char, CharType, "constChar", false) CharValue;
alias PrimitiveIntegerValue!(wchar, WcharType, "constWchar", false) WcharValue;
alias PrimitiveIntegerValue!(dchar, DcharType, "constDchar", false) DcharValue;

class FloatingPointValue(T, B) : Value
{
    this(Module mod, Location location)
    {
        super(mod, location);
        mType = new B(mod);
        if (!mGlobal) {
            mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "double");
        } else {
            mValue = LLVMAddGlobal(mod.mod, mType.llvmType, "tlsdouble");
            LLVMSetThreadLocal(mValue, true);
        }
    }
    
    this(Module mod, Location location, double d)
    {
        this(mod, location);
        constInit(d);
    }
    
    override Value performCast(Location location, Type t)
    {
        auto v = t.getValue(mModule, location);
        if (isIntegerDType(t.dtype)) {
            v.set(LLVMBuildFPToSI(mModule.builder, get(), t.llvmType, "cast"));
        } else if (isFPDtype(t.dtype)) {
            throw new CompilerPanic(location, "floating point to floating point casts are unimplemented.");
        } else {
            throw new CompilerPanic(location, "invalid cast.");
        }
        return v;
    }
    
    version (none) override Value importToModule(Module mod)
    {
        throw new CompilerPanic("attempted to import double value across modules.");
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "doubleget");
    }
    
    override void set(Value val)
    {
        setPreCallbacks();
        this.constant = this.constant && val.constant;
        if (this.constant) {
            this.constDouble = val.constDouble;
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
        setPostCallbacks();
    }
    
    override void initialise(Value val)
    {
        if (!mGlobal) {
            set(val);
        } else {
            if (!val.constant) {
                throw new CompilerError(location, "non-constant global initialiser.");
            }
            static if (is(T == float)) {
                initialise(LLVMConstReal(mType.llvmType, val.constFloat));
            } else if (is(T == double)) {
                initialise(LLVMConstReal(mType.llvmType, val.constDouble));
            } else if (is(T == real)) {
                initialise(LLVMConstReal(mType.llvmType, val.constReal));
            } else {
                assert(false, "unknown floating point type.");
            }
        }
    }
    
    override void initialise(LLVMValueRef val)
    {
        if (!mGlobal) {
            set(val);
        } else {
            LLVMSetInitializer(mValue, val);
        }
    }
    
    override void set(LLVMValueRef val)
    {
        constant = false;
        LLVMBuildStore(mModule.builder, val, mValue);
    }
    
    override Value add(Location location, Value val)
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
    
    override Value sub(Location location, Value val)
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
    
    override Value mul(Location location, Value val)
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
    
    override Value div(Location location, Value val)
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
    
    override Value getSizeof(Location loc)
    {
        return newSizeT(mModule, loc, T.sizeof);
    }
    
    override Value addressOf()
    {
        auto v = new PointerValue(mModule, location, mType);
        v.set(mValue);
        return v;
    }

    override Value init(Location location)
    {
        auto v = new typeof(this)(mModule, location);
        v.constant = true;
        return v;
    }
    
    protected void constInit(T d)
    {
        auto val = LLVMConstReal(mType.llvmType, d);
        LLVMBuildStore(mModule.builder, val, mValue);
        constant = true;
        constDouble = d;
    }
}

alias FloatingPointValue!(float, FloatType) FloatValue;
alias FloatingPointValue!(double, DoubleType) DoubleValue;
alias FloatingPointValue!(real, RealType) RealValue;

class ArrayValue : StructValue
{
    Type baseType;
    
    this(Module mod, Location location, Type baseType)
    {
        auto asArray = new ArrayType(mod, baseType);
        super(mod, location, asArray);
        this.baseType = baseType;
        mType = asArray;
    }
    
    override Value getMember(Location location, string name)
    {
        auto v = super.getMember(location, name);
        if (name == "length") {
            auto theSizeT = getSizeT(mModule);
            assert(v.type.dtype == theSizeT.dtype);
            mOldLength = v;
            v.addSetPostCallback((Value val)
                                {
                                    assert(val.type.dtype == theSizeT.dtype);
                                    auto ptr = getMember(location, "ptr");
                                    auto vl = [ptr, val];
                                    ptr.set(gcRealloc.call(location, [ptr.location, val.location], vl).performCast(location, ptr.type));
                                });
        }
        return v;
    }
    
    override Value index(Location location, Value val)
    {
        return getMember(location, "ptr").index(location, val);
    }
    
    protected Value mOldLength;
}

class StringValue : ArrayValue
{
    this(Module mod, Location location, string s)
    {
        auto base = new CharType(mod);
        super(mod, location, base);
        
        auto strLen = s.length;
        
        // String literals should be null-terminated
        if(s.length == 0 || s[$-1] != '\0') {
            s ~= '\0';
        }
        
        LLVMValueRef val = LLVMAddGlobal(mod.mod, LLVMArrayType(base.llvmType, s.length), "string");

        LLVMSetLinkage(val, LLVMLinkage.Internal);
        LLVMSetGlobalConstant(val, true);
        LLVMSetInitializer(val, LLVMConstString(s.ptr, s.length, true));
        
        auto ptr = getMember(location, "ptr");
        auto castedVal = LLVMBuildBitCast(mod.builder, val, ptr.type.llvmType, "string_pointer");
        ptr.set(castedVal);
        
        auto length = newSizeT(mod, location, strLen);
        StructValue.getMember(location, "length").set(length);
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
        if (!mGlobal) {
            mValue = LLVMBuildAlloca(mod.builder, mType.llvmType, "pv");
        } else {
            mValue = LLVMAddGlobal(mod.mod, mType.llvmType, "tlspv");
            LLVMSetThreadLocal(mValue, true);
        }
    }
    
    override Value performCast(Location location, Type t)
    {
        auto v = t.getValue(mModule, location);
        if (t.dtype == DType.Pointer) {
            v.set(LLVMBuildPointerCast(mModule.builder, get(), t.llvmType(), "pcast"));
        } else {
            throw new CompilerError(location, "cannot cast from pointer to non-pointer type.");
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
            setPreCallbacks();
            LLVMBuildStore(mModule.builder, val.get(), mValue);
            setPostCallbacks();
        }
    }
    
    override void set(LLVMValueRef val)
    {
        setPreCallbacks();
        LLVMBuildStore(mModule.builder, val, mValue);
        setPostCallbacks();
    }
    
    override void initialise(Value val)
    {
        if (!mGlobal) {
            set(val);
        } else {
            if (!val.constant) {
                throw new CompilerError(location, "non-constant global initialiser.");
            }
            initialise(val.get());
        }
    }
    
    override void initialise(LLVMValueRef val)
    {
        if (!mGlobal) {
            set(val);
        } else {
            LLVMSetInitializer(mValue, LLVMConstNull(mType.llvmType));  // HACK
        }
    }
    
    override Value dereference(Location location)
    {
        auto t = new IntType(mModule);
        LLVMValueRef[] indices;
        indices ~= LLVMConstInt(t.llvmType, 0, false);
        
        auto v = baseType.getValue(mModule, location);
        v.mValue = LLVMBuildGEP(mModule.builder, get(), indices.ptr, indices.length, "gep");
        return v;
    }
    
    override Value index(Location location, Value val)
    {
        val = implicitCast(location, val, new IntType(mModule));
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
        v.constant = true;
        return v;
    }
    
    override Value getMember(Location location, string name)
    {
        auto prop = getProperty(location, name);
        if (prop !is null) {
            return prop;
        }
        
        auto v = dereference(location);
        return v.getMember(location, name);
    }
    
    override Value getSizeof(Location loc)
    {
        return getSizeT(mModule).getValue(mModule, loc).getSizeof(loc);
    }
}

class NullPointerValue : PointerValue
{
    this(Module mod, Location location)
    {
        super(mod, location, new VoidType(mod));
        mType = new NullPointerType(mod);
        constant = true;
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
        
        storeSpecial();
        
        mValue = LLVMAddFunction(mod.mod, toStringz(mangledName), func.llvmType);
    }
    
    /**
     * If this is a special runtime function, store it away
     * for later use.
     */
    void storeSpecial()
    {
        if (mangledName == "malloc" && gcAlloc is null) {
            gcAlloc = this;
        } else if (mangledName == "realloc" && gcRealloc is null) {
            gcRealloc = this;
        }
    }
    
    protected string mangle(FunctionType type)
    {
        if (name == "main") {
            // TMP
            return "main";
        }
        auto s = startMangle();
        if (type.parentAggregate !is null) {
            mangleQualifiedName(s, type.parentAggregate.fullName);
        } else {
            if (mModule.name is null) {
                throw new CompilerPanic("null module name.");
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
    
    override Value call(Location location, Location[] argLocations, Value[] args)
    {
        // Check call with function signature.
        auto functionType = cast(FunctionType) mType;
        assert(functionType);
        
        if (functionType.varargs) {
            if (functionType.argumentTypes.length > args.length) {
                throw new CompilerError(
                    location, 
                    format("expected at least %s arguments, got %s.", functionType.argumentTypes.length, args.length),
                    new CompilerError(
                        functionType.argumentListLocation,
                        format(`parameters of "%s":`, this.name)
                    )
                );
             }
        } else if (functionType.argumentTypes.length != args.length) {
            location.column = location.wholeLine;
            throw new CompilerError(
                location, 
                format("expected %s arguments, got %s.", functionType.argumentTypes.length, args.length),
                    new CompilerError(
                        functionType.argumentListLocation,
                        format(`parameters of "%s":`, this.name)
                    )
            );
        }
        
        foreach (i, arg; functionType.argumentTypes) {
            try {
                args[i] = implicitCast(argLocations[i], args[i], arg);
            } catch (CompilerError error) {
                error.more = new CompilerError(
                    functionType.argumentLocations[i],
                    format(`argument #%s of function "%s":`, i + 1, this.name)
                );
                throw error;
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
        throw new CompilerPanic(location, "tried to get the init of a function value.");
    }
    
    override Value importToModule(Module mod)
    {
        auto f = new FunctionValue(mod, location, enforce(cast(FunctionType) mType.importToModule(mod)), name, mangledName);
        return f;
    }
    
    override Value getSizeof(Location loc)
    {
        auto asFunction = enforce(cast(FunctionType) mType);
        // This is how DMD does it. Seems fairly arbitrary to my mind.
        return asFunction.returnType.getValue(mModule, loc).getSizeof(loc);
    }
}


class StructValue : Value
{
    this(Module mod, Location location, StructType type)
    {
        super(mod, location);
        mType = type;
        if (!mGlobal) {
            mValue = LLVMBuildAlloca(mod.builder, type.llvmType, "struct");
        } else {
            mValue = LLVMAddGlobal(mod.mod, type.llvmType, "tlsstruct");
            LLVMSetThreadLocal(mValue, true);
            LLVMSetInitializer(mValue, LLVMGetUndef(type.llvmType));
        }
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "struct");
    }
    
    override void set(Value val)
    {
        setPreCallbacks();
        LLVMBuildStore(mModule.builder, val.get(), mValue);
        setPostCallbacks();
    }
    
    override void set(LLVMValueRef val)
    {
        setPreCallbacks();
        LLVMBuildStore(mModule.builder, val, mValue);
        setPostCallbacks();
    }
    
    override Value init(Location location)
    {
        auto asStruct = enforce(cast(StructType) mType);
        auto v = new StructValue(mModule, location, asStruct);
        foreach (member; asStruct.memberPositions.keys) {
            auto m = v.getMember(location, member);
            m.set(m.init(location));
        }
        return v;
    }
    
    override Value getMember(Location location, string name)
    {
        auto prop = getProperty(location, name);
        if (prop !is null) {
            return prop;
        }
        
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
    
    override Value getSizeof(Location loc)
    {
        auto v = getSizeT(mModule).getValue(mModule, loc);
        v.initialise(v.init(loc));
        auto asStruct = enforce(cast(StructType) mType);
        foreach (member; asStruct.members) {
            v = v.add(loc, member.getValue(mModule, loc).getSizeof(loc));
        }
        return v;
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
    
    override Value getMember(Location location, string name)
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
        t = primitiveTypeToBackendType(cast(ast.PrimitiveType) type.node, mod);
        break;
    case ast.TypeType.UserDefined:
        t = userDefinedTypeToBackendType(cast(ast.UserDefinedType) type.node, mod, onFailure);
        break;
    case ast.TypeType.Inferred:
        t = new InferredType(mod);
        break;
    default:
        throw new CompilerPanic(type.location, "unhandled type type.");
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
            throw new CompilerPanic(type.location, "unimplemented type suffix.");
        }
    }
    
    return t;
}

Type primitiveTypeToBackendType(ast.PrimitiveType type, Module mod)
{
    switch (type.type) {
    case ast.PrimitiveTypeType.Void:
        return new VoidType(mod);
    case ast.PrimitiveTypeType.Bool:
        return new BoolType(mod);
    case ast.PrimitiveTypeType.Byte:
        return new ByteType(mod);
    case ast.PrimitiveTypeType.Ubyte:
        return new UbyteType(mod);
    case ast.PrimitiveTypeType.Short:
        return new ShortType(mod);
    case ast.PrimitiveTypeType.Ushort:
        return new UshortType(mod);
    case ast.PrimitiveTypeType.Int:
        return new IntType(mod);
    case ast.PrimitiveTypeType.Uint:
        return new UintType(mod);
    case ast.PrimitiveTypeType.Long:
        return new LongType(mod);
    case ast.PrimitiveTypeType.Ulong:
        return new UlongType(mod);
    case ast.PrimitiveTypeType.Float:
        return new FloatType(mod);
    case ast.PrimitiveTypeType.Double:
        return new DoubleType(mod);
    case ast.PrimitiveTypeType.Real:
        return new RealType(mod);
    case ast.PrimitiveTypeType.Char:
        return new CharType(mod);
    case ast.PrimitiveTypeType.Wchar:
        return new WcharType(mod);
    case ast.PrimitiveTypeType.Dchar:
        return new DcharType(mod);
    default:
        throw new CompilerPanic(type.location, format("unhandled primitive type '%s'.", to!string(type.type)));
    }
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
                throw new CompilerError(type.location, format("undefined type '%s'.", name));
            } else {
                mod.addFailure(LookupFailure(name, type.location));
                return null;
            }
        } else if (store.storeType == StoreType.Value) {
            throw new CompilerError(type.location, format("'%s' is not a type.", name));
        } else if (store.storeType == StoreType.Type) {
            return store.type;
        } else if (store.storeType == StoreType.Scope) {
            baseScope = store.getScope();
        }
    }
    assert(false);
}

void binaryOperatorImplicitCast(Location location, Value* lhs, Value* rhs)
{    
    if (lhs.type.dtype == rhs.type.dtype) {
        return;
    }
 
    auto toDType = max(lhs.type.dtype, rhs.type.dtype);
    auto t = dtypeToType(toDType, lhs.getModule());
    if (lhs.type.dtype > rhs.type.dtype) {
        *rhs = implicitCast(location, *rhs, t);
    } else {
        *lhs = implicitCast(location, *lhs, t);
    }
}

Value implicitCast(Location location, Value v, Type toType)
{
    switch(toType.dtype) {
    case DType.Pointer:
        if (v.type.dtype == DType.NullPointer) {
            return v;
        }
        else if (v.type.dtype == DType.Pointer) {
            if(v.type.getBase().dtype == toType.getBase().dtype) {
                return v;
            }
        }
        else if (v.type.dtype == DType.Array) {
            if(v.type.getBase().dtype == toType.getBase().dtype) {
                return v.getMember(location, "ptr");
            }
        }
        break;
    case DType.Array:
        if (v.type.dtype == DType.Array) {
            if (v.type.getBase().dtype == toType.getBase().dtype) {
                return v;
            }
        }
        break;
    case DType.Complex: .. case DType.max:
        throw new CompilerPanic(location, "casts involving complex types are unimplemented.");
    default:
        if (toType.dtype == v.type.dtype) {
            return v;
        } else if (canImplicitCast(v.type.dtype, toType.dtype)) {
            return v.performCast(location, toType);
        }
        break;
    }
    throw new CompilerError(location, format("cannot implicitly cast '%s' to '%s'.", v.type.name(), toType.name()));
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
}
