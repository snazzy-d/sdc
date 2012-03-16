/**
 * Copyright 2010-2011 Bernard Helyer.
 * Copyright 2010-2011 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.value;

import std.algorithm;
import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;

import llvm.c.Core;
import llvm.Ext;

import sdc.util;
import sdc.mangle;
import sdc.extract;
import sdc.compilererror;
import sdc.location;
import sdc.aglobal;
import sdc.gen.cfg;
import sdc.gen.expression;
import sdc.gen.sdcmodule;
import sdc.gen.sdctemplate;
import sdc.gen.sdcfunction;
import sdc.gen.type;
import ast = sdc.ast.all;


/**
 * Value represents an instance of a given type.
 * Every expression, even if temporary, will generate a Value.
 */
abstract class Value
{
    /// The location that this Value was created at.
    Location location;
    /// The access level that this Value inherited.
    ast.Access access;
    /// If Value.lvalue is false, it can't be modified using set. 
    bool lvalue = false;
    
    ast.QualifiedName humanName;  // Optional.
    string mangledName;  // Optional.
    
    /// The Module this Value is associated with.
    protected Module mModule;
    /// The type this Value is an instance of.
    protected Type mType;
    /**
     * The underlying LLVM value for this Value.
     * All types are stored as pointers to their types,
     * so int's are stored as int*. To get the actual
     * value use the get method.
     */
    package LLVMValueRef mValue;
    /// If true, this value was created at a global scope.
    protected bool mGlobal;
    /// Callbacks that are called before a set takes place.
    protected void delegate(Value val)[] mSetPreCallbacks;
    /// Callbacks that are called after a set takes place.
    protected void delegate(Value val)[] mSetPostCallbacks;
    protected bool mIsKnown = false;
    
    /// All Values should be able to be created with just a Module and a Location.
    this(Module mod, Location loc)
    {
        mModule = mod;
        location = loc;
        access = mod.currentAccess;
        mGlobal = mod.currentScope is mod.globalScope;
    }
    
    /// If true, the value of this Value is known to the compiler.
    @property bool isKnown() { return mIsKnown; }
    @property void isKnown(bool b) { mIsKnown = b; }
    
    /// If isKnown, these are the types the compiler knows about, and contain the actual value.
    union
    {
        bool knownBool;
        byte knownByte;
        ubyte knownUbyte;
        short knownShort;
        ushort knownUshort;
        int knownInt;
        uint knownUint;
        long knownLong;
        ulong knownUlong;
        float knownFloat;  // Oh yes, we all float - and when you're down here with us, you'll float too!
        double knownDouble;
        real knownReal;
        char knownChar;
        wchar knownWchar;
        dchar knownDchar;
        string knownString;
    }
    
    Type type() @property
    {
        return mType;
    }
    
    void type(Type t) @property
    {
        mType = t;
    }
    
    /**
     * Generate code to cast this Value to the given type.
     * This method isn't concerned with narrowing or the like.
     */
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

    /// Retrieve the actual LLVM value that matches the Type. 
    LLVMValueRef get() { fail("get"); assert(false); }
    
    /// Retrieve a reference to this value as an LLVM constant.
    LLVMValueRef getConstant() { fail("get constant"); assert(false); }
    
    /// Set Value's value. Is affected by lvalue.
    void set(Location location, Value val) { fail("set (by Value)"); assert(false); }
    void set(Location location, LLVMValueRef val) { fail("set (by LLVMValueRef)"); assert(false); }
    /// The same as set, but not affected by lvalue.
    void initialise(Location location, Value val) 
    {
        const bool islvalue = lvalue;
        lvalue = true; 
        set(location, val);
        lvalue = islvalue; 
    }
    void initialise(Location location, LLVMValueRef val) 
    { 
        const bool islvalue = lvalue;
        lvalue = true;
        set(location, val);
        lvalue = islvalue; 
    }
    
    /** 
     * Most of the operators don't modify this instance,
     * instead creating a new one. Even inc and dec.
     * Obvious exceptions are set and initialise.
     */
    
    Value add(Location loc, Value val) { fail(loc, "add"); assert(false); }  /// +
    Value inc(Location loc) { fail(loc, "increment"); assert(false); }  /// v + 1
    Value dec(Location loc) { fail(loc, "decrement"); assert(false); }  /// v - 1
    Value sub(Location loc, Value val) { fail(loc, "subtract"); assert(false); }  /// -
    Value mul(Location loc, Value val) { fail(loc, "multiply"); assert(false); }  /// *
    Value div(Location loc, Value val) { fail(loc, "divide"); assert(false); }  /// /
    Value eq(Location loc, Value val) { fail(loc, "compare equality of"); assert(false); }   /// ==
    Value identity(Location loc, Value val) { return eq(loc, val); }  /// is
    Value nidentity(Location loc, Value val) { return neq(loc, val); }  /// !is
    Value neq(Location loc, Value val) { fail(loc, "compare non-equality of"); assert(false); }  /// !=
    Value gt(Location loc, Value val) { fail(loc, "compare greater-than of"); assert(false); }  /// >
    Value lt(Location loc, Value val) { fail(loc, "compare less-than of"); assert(false); }  /// <
    Value lte(Location loc, Value val) { fail(loc, "compare less-than of"); assert(false); }  /// <=
    Value or(Location loc, Value val) { fail(loc, "or"); assert(false); }  /// |
    Value and(Location loc, Value val) { fail(loc, "and"); assert(false); }  /// &
    Value xor(Location loc, Value val) { fail(loc, "xor"); assert(false); }  /// ^
    Value not(Location loc) { fail(loc, "not"); assert(false); }  /// ~
    Value dereference(Location loc) { fail(loc, "dereference"); assert(false); }  /// *v
    Value index(Location loc, Value val) { fail(loc, "index"); assert(false); }  /// [n]
    Value slice(Location loc, Value from, Value to) { fail(loc, "slice"); assert(false); }  /// [n .. m]  
    Value mod(Location loc, Value val) { fail(loc, "modulo"); assert(false); }  /// %
    Value getSizeof(Location loc) { fail(loc, "getSizeof"); assert(false); }  /// .sizeof
    
    /// ||
    Value logicalOr(Location location, Value val)
    {
        auto boolType = new BoolType(mModule);
        auto a = this.performCast(location, boolType);
        auto b = val.performCast(location, boolType);
        return a.or(location, b);
    }
    
    /// &&
    Value logicalAnd(Location location, Value val)
    {
        auto boolType = new BoolType(mModule);
        auto a = this.performCast(location, boolType);
        auto b = val.performCast(location, boolType);
        return a.and(location, b);
    }
    
    /// !
    Value logicalNot(Location location)
    {
        auto boolType = new BoolType(mModule);
        auto a = this.performCast(location, boolType);
        return a.not(location);
    }
    
    /// &v
    Value addressOf(Location location)
    {
        //errorIfNotLValue(location, "cannot take the address of an rvalue.");
        auto v = new PointerValue(mModule, location, mType);
        v.initialise(location, mValue);
        return v;
    }
    
    Value getProperty(Location loc, string name)
    {
        switch (name) {
        case "getInit":
            return getInit(loc);
        case "sizeof":
            return getSizeof(loc);
        default:
            return null;
        }
    }
    
    Value getMember(Location loc, string name)
    {
        return getProperty(loc, name);
    }
    
    Value call(Location location, Location[] argLocations, Value[] args) { fail("call"); assert(false); }
    Value getInit(Location location) { fail("getInit"); assert(false); }
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
    
    void errorIfNotLValue(Location location, string msg = "cannot modify rvalue.")
    {
        if (!lvalue) {
            throw new CompilerError(location, msg);
        }
    }
    
    /**
     * Override this to convert a known value to a string.
     * Is allowed to assume that isKnown is true.
     * Do not call directly - use toKnownString.
     */
    protected string getKnownAsString()
    {
        auto className = typeid(this).name;
        throw new CompilerPanic(location, format("%s does not implement getKnownAsString().", className));
    }
    
    final string toKnownString()
    {
        if (!isKnown) {
            throw new CompilerPanic(location, "attempt to toKnownString() on non-isKnown value.");
        }
        return getKnownAsString();
    }
}

mixin template SimpleImportToModule()
{
    override Value importToModule(Module mod)
    {
        auto v = new typeof(this)(mod, location);
        v.access = this.access;
        v.lvalue = this.lvalue;
        if (this.isKnown) {
            v.isKnown = true;
            switch (this.type.dtype) with (DType) {
            case Bool: v.knownBool = this.knownBool; break;
            case Byte: v.knownByte = this.knownByte; break;
            case Ubyte: v.knownUbyte = this.knownUbyte; break;
            case Short: v.knownShort = this.knownShort; break;
            case Ushort: v.knownUshort = this.knownUshort; break;
            case Int: v.knownInt = this.knownInt; break;
            case Uint: v.knownUint = this.knownUint; break;
            case Long: v.knownLong = this.knownLong; break;
            case Ulong: v.knownUlong = this.knownUlong; break;
            case Float: v.knownFloat = this.knownFloat; break;
            case Double: v.knownDouble = this.knownDouble; break;
            case Real: v.knownReal = this.knownReal; break;
            case Char: v.knownChar = this.knownChar; break;
            case Dchar: v.knownDchar = this.knownDchar; break;
            case Wchar: v.knownWchar = this.knownWchar; break;
            default:
                if (v.knownString.length > 0) {
                    v.knownString = this.knownString;
                } else {    
                    v.isKnown = false;
                }
                break;
            }
        }
        return v;
    }
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

mixin template LLVMIntComparison(LLVMIntPredicate ComparisonType, string ComparisonString, string DOperator)
{
    mixin("override Value " ~ ComparisonString ~ "(Location location, Value val) {"
        "auto v = LLVMBuildICmp(mModule.builder, ComparisonType, get(), val.get(), toStringz(ComparisonString));"
        "auto b = new BoolValue(mModule, location);"
        "b.initialise(location, v);"
        "b.isKnown = isKnown && val.isKnown;"
        "if (b.isKnown) {"
        "    b.knownBool = knownBool " ~ DOperator ~ " val.knownBool;"
        "}"
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
            //TLS not implemented on Windows
            version(Windows){} else {
                LLVMSetThreadLocal(mValue, true);
            }
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
        set(location, val);
    }
    
    override Value performCast(Location location, Type t)
    {
        if (t.equals(mType)) {
            return this;
        }
        
        auto v = t.getValue(mModule, location);
        if (isIntegerDType(t.dtype)) {
            if (t.dtype == DType.Bool) {
                v.initialise(location, LLVMBuildNot(mModule.builder, this.eq(location, new typeof(this)(mModule, location, 0)).get(), "boolnot"));
            } else if (mType.dtype < t.dtype) {
                v.initialise(location, LLVMBuildZExt(mModule.builder, get(), t.llvmType, "cast"));
            } else if (mType.dtype > t.dtype) {
                v.initialise(location, LLVMBuildTrunc(mModule.builder, get(), t.llvmType, "cast"));
            } else {
                v.initialise(location, get());
            }
        } else if (isFPDtype(t.dtype)) {
            v.initialise(location, LLVMBuildUIToFP(mModule.builder, get(), t.llvmType, "cast"));
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
    
    // TODO: merge with get()?
    override LLVMValueRef getConstant()
    {
        if (!isKnown) {
            return super.getConstant();
        } else {
            return LLVMConstInt(mType.llvmType, mixin(C), !SIGNED);
        }
    }
    
    override void set(Location location, Value val)
    {
        errorIfNotLValue(location);
        setPreCallbacks();
        this.isKnown = this.isKnown && val.isKnown;
        if (this.isKnown) {
            mixin(C ~ " = val." ~ C ~ ";");
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
        setPostCallbacks();
    }
    
    override void set(Location location, LLVMValueRef val)
    {
        errorIfNotLValue(location);
        setPreCallbacks();
        isKnown = false;
        LLVMBuildStore(mModule.builder, val, mValue);
        setPostCallbacks();
    }
    
    override void initialise(Location location, Value val)
    {
        if (!mGlobal) {
            const bool islvalue = lvalue;
            lvalue = true;
            set(location, val);
            lvalue = islvalue;
        } else {
            if (!val.isKnown) {
                throw new CompilerError(val.location, "value is not known at compile time.");
            }
            initialise(location, LLVMConstInt(mType.llvmType, mixin("val." ~ C), !SIGNED));
        }
    }
    
    override void initialise(Location location, LLVMValueRef val)
    {
        if (!mGlobal) {
            const bool islvalue = lvalue;
            lvalue = true;
            set(location, val);
            lvalue = islvalue;
        } else {
            LLVMSetInitializer(mValue, val);
        }
    }
    
    override Value add(Location location, Value val)
    {
        auto result = LLVMBuildAdd(mModule.builder, this.get(), val.get(), "add");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            mixin("v." ~ C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " + val." ~ C ~ ");");
        }
        return v;
    }
    
    static if(!is(T == bool)) override Value inc(Location location)
    {
        auto v = new typeof(this)(mModule, location);
        auto one = new typeof(this)(mModule, location, 1);
        v.initialise(location, this.add(location, one));
        
        if (isKnown) {
            auto known = mixin(C);
            ++known;
            mixin("v." ~ C ~ " = known;");
            v.isKnown = true;
        }
        
        return v;
    }
    
    static if(!is(T == bool)) override Value dec(Location location)
    {
        auto v = new typeof(this)(mModule, location);
        auto one = new typeof(this)(mModule, location, 1);
        v.initialise(location, this.sub(location, one));
        
        if (isKnown) {
            auto known = mixin(C);
            --known;
            mixin("v." ~ C ~ " = known;");
            v.isKnown = true;
        }
        return v;
    }
    
    override Value sub(Location location, Value val)
    {
        auto result = LLVMBuildSub(mModule.builder, this.get(), val.get(), "sub");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            mixin("v." ~ C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " - val." ~ C ~ ");");
        }
        return v;
    }
    
    override Value mul(Location location, Value val)
    {
        auto result = LLVMBuildMul(mModule.builder, this.get(), val.get(), "mul");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            mixin("v." ~ C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " * val." ~ C ~ ");");
        }
        return v;
    }
    
    override Value div(Location location, Value val)
    {
        static if (SIGNED) {
            auto result = LLVMBuildSDiv(mModule.builder, this.get(), val.get(), "div");
        } else {
            auto result = LLVMBuildUDiv(mModule.builder, this.get(), val.get(), "div");
        }
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            mixin("v." ~ C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " / val." ~ C ~ ");");
        }
        return v;
    }
    
    override Value mod(Location location, Value val)
    {
        static if (SIGNED) {
            auto result = LLVMBuildSRem(mModule.builder, this.get(), val.get(), "mod");
        } else {
            auto result = LLVMBuildURem(mModule.builder, this.get(), val.get(), "mod");
        }
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            mixin("v." ~ C ~ " = cast(" ~ T.stringof ~ ")(" ~ C ~ " % val." ~ C ~ ");");
        }
        return v;
    }
    
    override Value or(Location location, Value val)
    {
        auto result = LLVMBuildOr(mModule.builder, this.get(), val.get(), "or");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        return v;
    }
    
    override Value and(Location location, Value val)
    {
        auto result = LLVMBuildAnd(mModule.builder, this.get(), val.get(), "and");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        return v;
    }
    
    override Value xor(Location location, Value val)
    {
        auto result = LLVMBuildXor(mModule.builder, this.get(), val.get(), "xor");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        return v;
    }
    
    override Value not(Location location)
    {
        auto result = LLVMBuildNot(mModule.builder, this.get(), "not");
        auto v = new typeof(this)(mModule, location);
        v.initialise(location, result);
        return v;
    }
    
    override Value getSizeof(Location location)
    {
        return newSizeT(mModule, location, T.sizeof);
    }
    
    mixin LLVMIntComparison!(LLVMIntPredicate.EQ, "eq", "==");
    mixin LLVMIntComparison!(LLVMIntPredicate.NE, "neq", "!=");
    static if (SIGNED) {
        mixin LLVMIntComparison!(LLVMIntPredicate.SGT, "gt", ">");
        mixin LLVMIntComparison!(LLVMIntPredicate.SLT, "lt", "<");
        mixin LLVMIntComparison!(LLVMIntPredicate.SLE, "lte", "<=");
    } else {
        mixin LLVMIntComparison!(LLVMIntPredicate.UGT, "gt", ">");
        mixin LLVMIntComparison!(LLVMIntPredicate.ULT, "lt", "<");
        mixin LLVMIntComparison!(LLVMIntPredicate.ULE, "lte", "<=");
    }
    
    
    override Value getInit(Location location)
    {
        return new typeof(this)(mModule, location, 0);
    }
    
    mixin SimpleImportToModule;
        
    protected void constInit(T n)
    {
        auto val = LLVMConstInt(mType.llvmType(), n, !SIGNED);
        initialise(location, val);
        isKnown = true;
        mixin(C ~ " = n;");
    }
    
    override string getKnownAsString()
    {
        return to!string(mixin(C));
    }
}

alias PrimitiveIntegerValue!(bool, BoolType, "knownBool", true) BoolValue;
alias PrimitiveIntegerValue!(byte, ByteType, "knownByte", true) ByteValue;
alias PrimitiveIntegerValue!(ubyte, UbyteType, "knownUbyte", false) UbyteValue;
alias PrimitiveIntegerValue!(short, ShortType, "knownShort", true) ShortValue;
alias PrimitiveIntegerValue!(ushort, UshortType, "knownUshort", false) UshortValue;
alias PrimitiveIntegerValue!(int, IntType, "knownInt", true) IntValue;  
alias PrimitiveIntegerValue!(uint, UintType, "knownUint", false) UintValue;
alias PrimitiveIntegerValue!(long, LongType, "knownLong", true) LongValue;
alias PrimitiveIntegerValue!(ulong, UlongType, "knownUlong", false) UlongValue;
alias PrimitiveIntegerValue!(char, CharType, "knownChar", false) CharValue;
alias PrimitiveIntegerValue!(wchar, WcharType, "knownWchar", false) WcharValue;
alias PrimitiveIntegerValue!(dchar, DcharType, "knownDchar", false) DcharValue;

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
            //TLS not implemented on Windows
            version(Windows){} else {
                LLVMSetThreadLocal(mValue, true);
            }
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
            v.initialise(location, LLVMBuildFPToSI(mModule.builder, get(), t.llvmType, "cast"));
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
    
    override void set(Location location, Value val)
    {
        errorIfNotLValue(location);
        setPreCallbacks();
        this.isKnown = this.isKnown && val.isKnown;
        if (this.isKnown) {
            this.knownDouble = val.knownDouble;
        }
        LLVMBuildStore(mModule.builder, val.get(), mValue);
        setPostCallbacks();
    }
    
    override void initialise(Location location, Value val)
    {
        if (!mGlobal) {
            const bool islvalue = lvalue;
            lvalue = true;
            set(location, val);
            lvalue = islvalue;
        } else {
            if (!val.isKnown) {
                throw new CompilerError(location, "non-isKnown global initialiser.");
            }
            static if (is(T == float)) {
                initialise(location, LLVMConstReal(mType.llvmType, val.knownFloat));
            } else if (is(T == double)) {
                initialise(location, LLVMConstReal(mType.llvmType, val.knownDouble));
            } else if (is(T == real)) {
                initialise(location, LLVMConstReal(mType.llvmType, val.knownReal));
            } else {
                assert(false, "unknown floating point type.");
            }
        }
    }
    
    override void initialise(Location location, LLVMValueRef val)
    {
        if (!mGlobal) {
            const bool islvalue = lvalue;
            lvalue = true;
            set(location, val);
            lvalue = islvalue;
        } else {
            LLVMSetInitializer(mValue, val);
        }
    }
    
    override void set(Location location, LLVMValueRef val)
    {
        errorIfNotLValue(location);
        isKnown = false;
        LLVMBuildStore(mModule.builder, val, mValue);
    }
    
    override Value add(Location location, Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFAdd(mModule.builder, this.get(), val.get(), "fadd");
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            v.knownDouble = this.knownDouble + val.knownDouble;
        }
        return v;
    }
    
    override Value sub(Location location, Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFSub(mModule.builder, this.get(), val.get(), "fsub");
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            v.knownDouble = this.knownDouble - val.knownDouble;
        }
        return v;
    }
    
    override Value mul(Location location, Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFMul(mModule.builder, this.get(), val.get(), "fmul");
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            v.knownDouble = this.knownDouble * val.knownDouble;
        }
        return v;
    }
    
    override Value div(Location location, Value val)
    {
        auto v = new DoubleValue(mModule, location);
        auto result = LLVMBuildFDiv(mModule.builder, this.get(), val.get(), "fdiv");
        v.initialise(location, result);
        v.isKnown = this.isKnown && val.isKnown;
        if (v.isKnown) {
            v.knownDouble = this.knownDouble / val.knownDouble;
        }
        return v;
    }
    
    override Value getSizeof(Location loc)
    {
        return newSizeT(mModule, loc, T.sizeof);
    }
    
    override Value addressOf(Location location)
    {
        auto v = new PointerValue(mModule, location, mType);
        v.initialise(location, mValue);
        return v;
    }

    override Value getInit(Location location)
    {
        auto v = new typeof(this)(mModule, location);
        v.isKnown = true;
        return v;
    }
    
    mixin SimpleImportToModule;
    
    protected void constInit(T d)
    {
        auto val = LLVMConstReal(mType.llvmType, d);
        LLVMBuildStore(mModule.builder, val, mValue);
        isKnown = true;
        knownDouble = d;
    }
}

alias FloatingPointValue!(float, FloatType) FloatValue;
alias FloatingPointValue!(double, DoubleType) DoubleValue;
alias FloatingPointValue!(real, RealType) RealValue;

class StaticArrayValue : Value
{
    StaticArrayType asStaticArray;
    Type baseType;
    
    this(Module mod, Location location, Type baseType, Value lengthValue)
    {
        super(mod, location);
        if (!lengthValue.isKnown || lengthValue.type.dtype != DType.Int) {
            // !!!
            throw new CompilerError(location, "static arrays must be initialized with a known integer (temporary hack).");
        } 
        this.baseType = baseType;
        mType = asStaticArray = new StaticArrayType(mod, baseType, lengthValue.knownInt);
        LLVMBuildAlloca(mod.builder, mType.llvmType, "static_array");
    }
    
    override Value getSizeof(Location location)
    {
        // T[N].sizeof => T.sizeof * N
        return newSizeT(mModule, location, asStaticArray.length).mul(location, baseType.getValue(mModule, location).getSizeof(location));
    }
    
    override Value getMember(Location location, string name)
    {
        auto v = super.getMember(location, name);
        if (name == "length") {
            return newSizeT(mModule, location, asStaticArray.length);
        }
        return v;
    }
    
    override Value index(Location location, Value value)
    {
        auto t = new IntType(mModule);
        
        LLVMValueRef[] indices;
        indices ~= LLVMConstInt(t.llvmType, 0, false);
        indices ~= value.get();
        
        auto i = baseType.getValue(mModule, location);
        i.mValue = LLVMBuildGEP(mModule.builder, mValue, indices.ptr, cast(uint) indices.length, "gep");
        i.lvalue = true;
        return i;
    }
}

class ArrayValue : StructValue
{
    Type baseType;
    bool suppressCallbacks;
    
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
                                    if (suppressCallbacks) return;
                                    assert(val.type.dtype == theSizeT.dtype);
                                    auto ptr = getMember(location, "ptr");
                                    auto vl = [ptr.performCast(location, new PointerType(mModule, new VoidType(mModule))), val];
                                    auto memptr = mModule.gcRealloc(location, ptr, val);
                                    ptr.set(location, memptr.performCast(location, ptr.type));
                                });
        }
        return v;
    }
    
    override Value index(Location location, Value val)
    {   
        auto v = getMember(location, "ptr").index(location, val);
        v.lvalue = lvalue;
        return v;
    }
    
    override Value slice(Location location, Value from, Value to)
    {
        auto v = getMember(location, "ptr").slice(location, from, to);
        v.lvalue = lvalue;
        return v;
    }
    
    override Value importToModule(Module mod)
    {
        return new ArrayValue(mod, location, baseType.importToModule(mod));
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
        if (s.length == 0 || s[$-1] != '\0') {
            s ~= '\0';
        }
        
        isKnown = true;
        knownString = s[0..$-1]; // Null terminated, but null terminator not part of the array.
        
        val = LLVMAddGlobal(mod.mod, LLVMArrayType(base.llvmType, cast(uint) s.length), "string");

        LLVMSetLinkage(val, LLVMLinkage.Internal);
        LLVMSetGlobalConstant(val, true);
        LLVMSetInitializer(val, LLVMConstString(s.ptr, cast(uint) s.length, true));
        
        auto ptr = getMember(location, "ptr");
        assert(ptr !is null);
        auto castedVal = LLVMBuildBitCast(mod.builder, val, ptr.type.llvmType, "string_pointer");
        ptr.set(location, castedVal);
        
        auto length = newSizeT(mod, location, strLen);
        StructValue.getMember(location, "length").set(location, length);
    }
    
    LLVMValueRef val;
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
            
            //TLS not implemented on Windows
            version(Windows){} else {
                LLVMSetThreadLocal(mValue, true);
            }
        }
    }
    
    override Value performCast(Location location, Type t)
    {
        auto v = t.getValue(mModule, location);
        if (t.dtype == DType.Pointer) {
            v.initialise(location, LLVMBuildPointerCast(mModule.builder, get(), t.llvmType(), "pcast"));
        } else {
            throw new CompilerError(location, "cannot cast from pointer to non-pointer type.");
        }
        return v;
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "get");
    }
    
    override void set(Location location, Value val)
    {
        errorIfNotLValue(location);
        if (val.type.dtype == DType.NullPointer) {
            set(location, getInit(location));
        } else {
            setPreCallbacks();
            LLVMBuildStore(mModule.builder, val.get(), mValue);
            setPostCallbacks();
        }
    }
    
    override void set(Location location, LLVMValueRef val)
    {
        errorIfNotLValue(location);
        setPreCallbacks();
        LLVMBuildStore(mModule.builder, val, mValue);
        setPostCallbacks();
    }
    
    override void initialise(Location location, Value val)
    {
        if (!mGlobal) {
            const bool islvalue = lvalue;
            lvalue = true;
            set(location, val);
            lvalue = islvalue;
        } else {
            if (!val.isKnown) {
                throw new CompilerError(location, "non-isKnown global initialiser.");
            }
            initialise(location, val.get());
        }
    }
    
    override void initialise(Location location, LLVMValueRef val)
    {
        if (!mGlobal) {
            const bool islvalue = lvalue;
            lvalue = true;
            set(location, val);
            lvalue = islvalue;
        } else {
            LLVMSetInitializer(mValue, LLVMConstNull(mType.llvmType));  // HACK
        }
    }
    
    override Value dereference(Location location)
    {
        auto v = baseType.getValue(mModule, location);
        v.mValue = LLVMBuildLoad(mModule.builder, mValue, "dereference");
        return v;
    }
    
    private final Value pointerArithmetic(Location location, Value idx)
    {
        idx = implicitCast(location, idx, getPtrdiffT(mModule));
       
        auto idxVal = idx.get();
        auto added = LLVMBuildGEP(mModule.builder, get(), &idxVal, 1, "ptradd");
        
        auto v = mType.getValue(mModule, location);
        LLVMBuildStore(mModule.builder, added, v.mValue);
        return v;
    }
    
    override Value add(Location location, Value idx)
    {
        return pointerArithmetic(location, idx);
    }
    
    override Value inc(Location location)
    {
        return pointerArithmetic(location, newPtrdiffT(mModule, location, 1));
    }
    
    override Value sub(Location location, Value idx)
    {
        idx = implicitCast(location, idx, getPtrdiffT(mModule));
        auto zero = newPtrdiffT(mModule, location, 0);
        return pointerArithmetic(location, zero.sub(location, idx));
    }
    
    override Value dec(Location location)
    {
        return pointerArithmetic(location, newPtrdiffT(mModule, location, -1));
    }
    
    override Value index(Location location, Value val)
    {
        val = implicitCast(location, val, getSizeT(mModule));
        LLVMValueRef[] indices;
        indices ~= val.get();
        
        auto v = baseType.getValue(mModule, location);
        v.mValue = LLVMBuildGEP(mModule.builder, get(), indices.ptr, cast(uint) indices.length, "index");
        v.lvalue = lvalue;
        return v;
    }
    
    override Value slice(Location location, Value from, Value to)
    {
        from = implicitCast(location, from, getSizeT(mModule));
        to = implicitCast(location, to, getSizeT(mModule));
        
        auto arrayType = new ArrayType(mModule, baseType);
        auto v = arrayType.getValue(mModule, location);
        v.suppressCallbacks = true;
        v.getMember(location, "ptr").set(location, add(location, from));
        v.getMember(location, "length").set(location, to.sub(location, from));
        v.suppressCallbacks = false;
        return v;
    }
    
    override Value eq(Location location, Value val)
    {
        auto retval = new BoolValue(mModule, location);
        if (val.type.dtype == DType.NullPointer) {
            retval.initialise(location, LLVMBuildIsNull(mModule.builder, get(), "is"));
        } else {
            retval.initialise(location, LLVMBuildICmp(mModule.builder, LLVMIntPredicate.EQ, get(), val.get(), "is"));
        }
        return retval;
    }
    
    override Value getInit(Location location)
    {
        auto v = new PointerValue(mModule, location, baseType);
        v.initialise(location, LLVMConstNull(v.mType.llvmType));
        v.isKnown = true;
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
    
    override Value call(Location location, Location[] argLocations, Value[] args)
    {
        if (baseType.dtype == DType.Function) {
            return buildCall(mModule, cast(FunctionType) baseType, LLVMBuildLoad(mModule.builder, mValue, "callload"), 
                             "function pointer", location, argLocations, args);
        } else {
            auto v = dereference(location);
            return v.call(location, argLocations, args);
        }
    }
    
    override Value getSizeof(Location loc)
    {
        return getSizeT(mModule).getValue(mModule, loc).getSizeof(loc);
    }
    
    override Value importToModule(Module mod)
    {
        return new PointerValue(mod, location, baseType.importToModule(mod));
    }
    
    mixin LLVMIntComparison!(LLVMIntPredicate.EQ, "eq", "==");
    mixin LLVMIntComparison!(LLVMIntPredicate.NE, "neq", "!=");
    mixin LLVMIntComparison!(LLVMIntPredicate.UGT, "gt", ">");
    mixin LLVMIntComparison!(LLVMIntPredicate.ULT, "lt", "<");
    mixin LLVMIntComparison!(LLVMIntPredicate.ULE, "lte", "<=");
}

mixin template ReferenceImplementation(alias SIGNATURE, alias CALL)
{
    mixin("override Value " ~ SIGNATURE ~ "{ return pointerToBase.dereference(loc)." ~ CALL ~ "; }");
}

mixin template BinaryReferenceImplementation(alias NAME)
{
    mixin ReferenceImplementation!(NAME ~ "(Location loc, Value val)", NAME ~ "(loc, val)");
}

mixin template UnaryReferenceImplementation(alias NAME)
{
    mixin ReferenceImplementation!(NAME ~ "(Location loc)", NAME ~ "(loc)");
}

class ReferenceValue : Value
{
    Value base;
    PointerValue pointerToBase;
    
    this(Module mod, Location location, Value base)
    {
        super(mod, location);
        this.base = base;
        mType = base.type;
        mValue = base.mValue;
        pointerToBase = new PointerValue(mod, location, base.type);
        setReferencePointer(location, base.addressOf(location).get());
    }
    
    void setReferencePointer(Location loc, LLVMValueRef val)
    {
        pointerToBase.initialise(loc, val);
    }
    
    override LLVMValueRef get()
    {
        return pointerToBase.dereference(location).get();
    }
    
    override void set(Location loc, Value val)
    {
        errorIfNotLValue(loc);
        setPreCallbacks();
        pointerToBase.dereference(loc).initialise(loc, val);
        setPostCallbacks();
    }
    
    override void set(Location loc, LLVMValueRef val)
    {
        errorIfNotLValue(loc);
        setPreCallbacks();
        pointerToBase.dereference(loc).set(loc, val);
        setPostCallbacks();
    }
    
    mixin MultiMixin!(UnaryReferenceImplementation, "inc", "dec", "dereference", 
                      "getSizeof", "getInit");
    mixin MultiMixin!(BinaryReferenceImplementation, "add", "sub", "mul", "div", 
                      "eq", "neq", "gt", "lt", "lte", "index", "mod");
    
    override Value getMember(Location loc, string name)
    {
        return pointerToBase.dereference(loc).getMember(loc, name);
    }    
    
    override Value importToModule(Module mod)
    {
        return new ReferenceValue(mod, location, base.importToModule(mod));
    }
}

class ClassValue : Value
{
    PointerValue v;
    this(Module mod, Location location, ClassType t)
    {
        super(mod, location);
        mType = t;
        v = new PointerValue(mod, location, t.structType);
        mValue = v.mValue;
        v.lvalue = true;
        lvalue = true;
    }
    
    override Value getInit(Location location)
    {
        return new NullPointerValue(mModule, location);
    }
    
    override LLVMValueRef get()
    {
        return v.get();
    }
    
    override void set(Location loc, Value val)
    {
        errorIfNotLValue(loc);
        setPreCallbacks();
        if (val.type.dtype == DType.Class) {
            auto asClass = enforce(cast(ClassValue) val);
            v.set(loc, asClass.v);
        } else {
            v.set(loc, val);
        }
        setPostCallbacks();
    }
    
    override void set(Location loc, LLVMValueRef val)
    {
        errorIfNotLValue(loc);
        setPreCallbacks();
        v.set(loc, val);
        setPostCallbacks();
    }
    
    override void initialise(Location loc, Value val)
    {
        auto oldlvalue = lvalue;
        lvalue = true;
        set(loc, val);
        lvalue = oldlvalue;
    }
    
    override void initialise(Location loc, LLVMValueRef val)
    {
        auto oldlvalue = lvalue;
        lvalue = true;
        set(loc, val);
        lvalue = oldlvalue;
    }
    
    override Value getMember(Location location, string name)
    {
        auto asClass = enforce(cast(ClassType) mType);
        if (auto p = name in asClass.methodIndices) {
            // *p + 1 because the first entry of the vtable contains a TypeInfo instance. 
            auto fptr = v.getMember(location, "__vptr").index(location, newSizeT(mModule, location, *p + 1));
            auto fntype = new PointerType(mModule, asClass.methods[*p].fn.type);
            return fptr.performCast(location, fntype);
        }
        return v.getMember(location, name);
    }
    
    override Value getSizeof(Location location)
    {
        return v.getSizeof(location);
    }
    
    mixin ImportToModule!(Value, "mod, location, cast(ClassType) mType.importToModule(mod)");
}

mixin template BinaryReferenceWrapperImplementation(alias NAME)
{
    mixin("override Value " ~ NAME ~ "(Location loc, Value val) { return new typeof(this)(mModule, loc, base." ~ NAME ~ "(loc, val)); }");
}

class ConstValue : Value
{
    Value base;
    
    this(Module mod, Location location, Value base)
    {
        super(mod, location);
        this.base = base;
        mType = new ConstType(mod, base.type);
        mValue = base.mValue;
    }
    
    override Value getInit(Location location)
    {
        return base.getInit(location);
    }
        
    override void set(Location location, Value val)
    {
        throw new CompilerError(location, "cannot modify const value.");
    }
    
    override void set(Location location, LLVMValueRef val)
    {
        throw new CompilerError(location, "cannot modify const value.");
    }
    
    override void initialise(Location location, Value val)
    {
        base.initialise(location, val);
    }
    
    override void initialise(Location location, LLVMValueRef val)
    {
        base.initialise(location, val);
    }
    
    override Value performCast(Location location, Type t)
    {
        return base.performCast(location, t);
    }
    
    override LLVMValueRef get()
    {
        return base.get();
    }
    
    override Value getMember(Location location, string name)
    {
        auto member = base.getMember(location, name);
        if (member is null) {
            return null;
        }
        return new ConstValue(mModule, location, member);
    }
    
    override Value importToModule(Module mod)
    {
        return base.importToModule(mod);
    }
    
    override Value getSizeof(Location loc)
    {
        return base.getSizeof(loc);
    }
    
    override bool isKnown()
    {
        return base.isKnown;
    }
    
    mixin MultiMixin!(BinaryReferenceWrapperImplementation, "add", "sub", "mul", "div", 
                      "eq", "neq", "gt", "lt", "lte", "index", "mod");
}
class ImmutableValue : Value
{
    Value base;
    
    this(Module mod, Location location, Value base)
    {
        super(mod, location);
        this.base = base;
        mType = new ConstType(mod, base.type);
        mValue = base.mValue;
    }
    
    override Value getInit(Location location)
    {
        return base.getInit(location);
    }
        
    override void set(Location location, Value val)
    {
        throw new CompilerError(location, "cannot modify const value.");
    }
    
    override void set(Location location, LLVMValueRef val)
    {
        throw new CompilerError(location, "cannot modify const value.");
    }
    
    override void initialise(Location location, Value val)
    {
        base.initialise(location, val);
    }
    
    override void initialise(Location location, LLVMValueRef val)
    {
        base.initialise(location, val);
    }
    
    override Value performCast(Location location, Type t)
    {
        return base.performCast(location, t);
    }
    
    override LLVMValueRef get()
    {
        return base.get();
    }
    
    override Value getMember(Location location, string name)
    {
        auto member = base.getMember(location, name);
        if (member is null) {
            return null;
        }
        return new ImmutableValue(mModule, location, member);
    }
    
    override Value importToModule(Module mod)
    {
        return base.importToModule(mod);
    }
    
    override Value getSizeof(Location loc)
    {
        return base.getSizeof(loc);
    }
    
    override bool isKnown()
    {
        return base.isKnown;
    }
    
    mixin MultiMixin!(BinaryReferenceWrapperImplementation, "add", "sub", "mul", "div", 
                      "eq", "neq", "gt", "lt", "lte", "index", "mod");
}
class NullPointerValue : PointerValue
{
    this(Module mod, Location location)
    {
        super(mod, location, new VoidType(mod));
        mType = new NullPointerType(mod);
        isKnown = true;
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
            //TLS not implemented on Windows
            version(Windows){} else {
                LLVMSetThreadLocal(mValue, true);
            }
            LLVMSetInitializer(mValue, LLVMGetUndef(type.llvmType));
        }
    }
    
    override LLVMValueRef get()
    {
        return LLVMBuildLoad(mModule.builder, mValue, "struct");
    }
    
    override void set(Location location, Value val)
    {
        errorIfNotLValue(location);
        setPreCallbacks();
        LLVMBuildStore(mModule.builder, val.get(), mValue);
        setPostCallbacks();
    }
    
    override void set(Location location, LLVMValueRef val)
    {
        errorIfNotLValue(location);
        setPreCallbacks();
        LLVMBuildStore(mModule.builder, val, mValue);
        setPostCallbacks();
    }
    
    override Value getInit(Location location)
    {
        auto asStruct = enforce(cast(StructType) mType);
        auto v = new StructValue(mModule, location, asStruct);
        foreach (member; asStruct.memberPositions.keys) {
            auto m = v.getMember(location, member);
            assert(m !is null);
            m.set(location, m.getInit(location));
        }
        return v;
    }
    
    override Value getMember(Location location, string name)
    {
        auto store = type.typeScope.get(name);
        if (store !is null && store.storeType == StoreType.Type) {
            return store.type.getValue(mModule, location);
        }
        
        // Is it a built-in property?
        auto prop = getProperty(location, name);
        if (prop !is null) {
            return prop;
        }
        
        auto asStruct = cast(StructType) mType;
        assert(asStruct);
        
        // Is it a member function?
        if (auto fnp = name in asStruct.memberFunctions) {
            return new Functions(mModule, location, [*fnp]);
        }
        
        auto t = new IntType(mModule);
        LLVMValueRef[] indices;
        indices ~= LLVMConstInt(t.llvmType, 0, false);
        
        // Actually look for a member in the instance, then.
        size_t* index = name in asStruct.memberPositions;
        if (index is null) {
            return null;
        }
        indices ~= LLVMConstInt(t.llvmType, *index, false);
        
        auto i = asStruct.members[*index].getValue(mModule, location);
        i.mValue = LLVMBuildGEP(mModule.builder, mValue, indices.ptr, cast(uint) indices.length, "getMember");
        i.lvalue = true;
        return i;
    }
    
    override Value getSizeof(Location loc)
    {
        auto v = getSizeT(mModule).getValue(mModule, loc);
        v.initialise(location, v.getInit(loc));
        auto asStruct = enforce(cast(StructType) mType);
        foreach (member; asStruct.members) {
            v = v.add(loc, member.getValue(mModule, loc).getSizeof(loc));
        }
        return v;
    }
    
    mixin ImportToModule!(Value, "mod, location, cast(StructType) type.importToModule(mod)");
}

/* Why, genIdentifier, why!!! */
class EnumValue : Value
{
    this(Module mod, Location location, EnumType type)
    {
        super(mod, location);
        mType = type;
    }
    
    override Value getMember(Location location, string name)
    {
        auto prop = getProperty(location, name);
        if (prop !is null) {
            return prop;
        }
        
        auto asEnum = cast(EnumType) mType;
        assert(asEnum);
        
        if (auto p = name in asEnum.members) {
            return *p;
        } else {
            return null;
        }
    }
    
    override Value getSizeof(Location loc)
    {
        auto v = getSizeT(mModule).getValue(mModule, loc);
        v.initialise(loc, mType.getBase().getValue(mModule, loc).getSizeof(loc));
        return v;
    }
    
    mixin ImportToModule!(Value, "mod, location, cast(EnumType) mType.importToModule(mod)");
}

class ScopeValue : Value
{
    Scope _scope;
    
    this(Module mod, Location location, Scope _scope)
    {
        super(mod, location);
        this._scope = _scope;
        mType = new ScopeType(mod);
    }
    
    override Value getMember(Location location, string name)
    {
        auto store = _scope.get(name);
        if (store is null) {
            return null;
        }
        if (store.storeType == StoreType.Scope) {
            return new ScopeValue(mModule, location, store.getScope());
        } else if (store.storeType == StoreType.Value) {
            return _scope.get(name).value;
        } else if (store.storeType == StoreType.Function) {
            return new Functions(mModule, location, store.getFunctions());
        } else {
            assert(false, to!string(store.storeType));
        }
    }
    
    override Value importToModule(Module mod)
    {
        return new ScopeValue(mod, location, _scope);
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
    case ast.TypeType.ConstType:
        t = new ConstType(mod, astTypeToBackendType(cast(ast.Type) type.node, mod, onFailure));
        break;
    case ast.TypeType.ImmutableType:
        t = new ImmutableType(mod, astTypeToBackendType(cast(ast.Type) type.node, mod, onFailure));
        break;
    case ast.TypeType.Typeof:
        t = genTypeof(cast(ast.TypeofType) type.node, mod);
        break;
    case ast.TypeType.FunctionPointer:
        t = genFunctionPointerType(cast(ast.FunctionPointerType) type.node, mod, onFailure);
        break;
    default:
        throw new CompilerPanic(type.location, "unhandled type type.");
    }
    
    if (t is null) {
        return null;
    }        
    
    foreach (suffix; retro(type.suffixes)) {
        if (suffix.type == ast.TypeSuffixType.Pointer) {
            t = new PointerType(mod, t);
        } else if (suffix.type == ast.TypeSuffixType.Array) {
            t = new ArrayType(mod, t);
        } else {
            throw new CompilerPanic(type.location, "unimplemented type suffix.");
        }
    }
    
    foreach (storageType; type.storageTypes) switch (storageType) with (ast.StorageType) {
    case Const:
        t = new ConstType(mod, t);
        break;
    case Immutable:
        t = new ImmutableType(mod, t);
        break;
    case Auto:
        break;
    case Static:
        break;
    default:
        throw new CompilerPanic(type.location, "unimplemented storage type.");
    }
    
    return t;
}

Type genFunctionPointerType(ast.FunctionPointerType type, Module mod, OnFailure onFailure)
{
    auto returnType = astTypeToBackendType(type.returnType, mod, onFailure);
    bool varargs = type.parameters.varargs;
    Type[] params;
    foreach (param; type.parameters.parameters) {
        params ~= astTypeToBackendType(param.type, mod, onFailure);
        params[$ - 1].isRef = param.attribute == ast.ParameterAttribute.Ref;
    }
    auto ftype = new FunctionType(mod, returnType, params, varargs);
    ftype.linkage = type.linkage;
    ftype.declare();
    return new PointerType(mod, ftype);
}

Type[] genParameterList(ast.ParameterList parameterList, Module mod, OnFailure onFailure)
{
    Type[] list;
    foreach (parameter; parameterList.parameters) {
        list ~= astTypeToBackendType(parameter.type, mod, onFailure);
    }
    return list;
}

Type genTypeof(ast.TypeofType typeoftype, Module mod)
{
    Type t;
    final switch (typeoftype.type) with (ast.TypeofTypeType) {
    case Return:
        throw new CompilerPanic(typeoftype.location, "typeof(return) is unimplemented.");
    case This:
        throw new CompilerPanic(typeoftype.location, "typeof(this) is unimplemented.");
    case Super:
        throw new CompilerPanic(typeoftype.location, "typeof(super) is unimplemented.");
    case Expression:
        auto val = genExpression(typeoftype.expression, mod.dup);
        t = val.type;
        break;
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
    Scope baseScope;
    foreach (thing; type.segments) {
        if (!thing.isIdentifier) {
            genTemplateInstance(cast(ast.TemplateInstance) thing.node, mod);
        }
        auto identifier = cast(ast.Identifier) thing.node;
        Store store;
        auto name = extractIdentifier(identifier);
        if (baseScope !is null) {
            store = baseScope.get(name);
        } else {
            if (mod.aggregate !is null) {
                store = mod.aggregate.typeScope.get(name);
            }
            if (store is null) store = mod.search(name);
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
        } else if (store.storeType == StoreType.Function) {
            auto functions = store.getFunctions();
            if (functions.length > 1) {
                throw new CompilerPanic("Cannot retrieve type of overloaded function.");
            }
            return functions[0].type;
        }
    }
    assert(false);
}

void binaryOperatorImplicitCast(Location location, Value* v, Value* rhs)
{    
    if (v.type.dtype == rhs.type.dtype) {
        return;
    }
    
    if (v.type.dtype == DType.Pointer || // pointer arithmetic
        v.type.dtype == DType.NullPointer || rhs.type.dtype == DType.NullPointer) {
        return;
    }
 
    if (v.type.dtype > rhs.type.dtype) {
        *rhs = implicitCast(location, *rhs, v.type);
    } else {
        *v = implicitCast(location, *v, rhs.type);
    }
}

Value implicitCast(Location location, Value v, Type toType)
{
    Value[] aliasThisMatches;
    foreach (aliasThis; v.type.aliasThises) {
        // The type has an alias this declaration, so try it.
        auto aliasValue = v.getMember(location, aliasThis);
        if (aliasValue is null) {
            throw new CompilerPanic(location, "invalid alias this.");
        }
        if (aliasValue.type.dtype == DType.Function) {
            // If the alias points to a function, call it.
            auto asFunction = enforce(cast(FunctionType) aliasValue.type);
            if (asFunction.parentAggregate !is v.type) {
                throw new CompilerError(location, "alias this refers to non member function '" ~ aliasThis ~ "'.");
            }
            if (asFunction.parameterTypes.length != 0) {
                auto address = v.addressOf(location);
                if (asFunction.parameterTypes.length > 1 || asFunction.parameterTypes[0] != address.type) {
                    throw new CompilerError(location, "alias this refers to function with non this parameter.");
                } 
                aliasValue = aliasValue.call(location, [v.location], [v.addressOf(location)]);
            } else {
                aliasValue = aliasValue.call(location, null, null);
            }
        }
        try { 
            auto aliasV = implicitCast(location, aliasValue, toType);
            aliasThisMatches ~= aliasV;
        } catch (CompilerError) {
            // Try other alias thises, or just the base type.
        }
    }
    
    if (aliasThisMatches.length > 1) {
        throw new CompilerError(location, "multiple valid alias this declarations.");
    } else if (aliasThisMatches.length == 1) {
        return aliasThisMatches[0];
    }
    
    switch(toType.dtype) {
    case DType.Pointer:
        if (v.type.dtype == DType.NullPointer) {
            return v;
        } else if (v.type.dtype == DType.Pointer) {
            if (toType.getBase().dtype == DType.Void) {
                // All pointers are implicitly castable to void*.
                return v.performCast(location, toType); 
            }
            
            if (toType.getBase().dtype == DType.Const) {
                return implicitCast(location, v, toType.getBase());
            }
            
            /+if (toType.getBase().dtype == v.type.getBase().dtype) {
                return v;
            }+/
        } else if (v.type.dtype == DType.Array) {
            if (v.type.getBase().dtype == toType.getBase().dtype) {
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
    case DType.Class:
        if (v.type.dtype == DType.NullPointer) {
            auto asClass = enforce(cast(ClassType) toType);
            return v.performCast(location, new PointerType(v.mModule, asClass.structType)); 
        }
        return v;  // TMP
    case DType.Const:
        return new ConstValue(v.getModule(), location, v);
    case DType.Immutable:
        return new ImmutableValue(v.getModule(), location, v);
    default:
        if (canImplicitCast(location, v.type, toType)) {
            return v.performCast(location, toType);
        }
        break;
    }
    
    // TODO: do this earlier when equals() is better supported.
    if (toType.equals(v.type)) {
        return v;
    } else {
        throw new CompilerError(location, format("cannot implicitly cast '%s' to '%s'.", v.type.name(), toType.name()));
    }
}

bool canImplicitCast(Location location, Type from, Type to)
{
    switch (from.dtype) with (DType) {
    case Bool:
        return true;
    case Char:
    case Ubyte:
    case Byte:
        return to.dtype >= Char;
    case Wchar:
    case Ushort:
    case Short:
        return to.dtype >= Wchar;
    case Dchar:
    case Uint:
    case Int:
        return to.dtype >= Dchar;
    case Ulong:
    case Long:
        return to.dtype >= Ulong;
    case Float:
    case Double:
    case Real:
        return to.dtype >= Float;
    case Pointer:
    case NullPointer:
        return to.dtype == Pointer || to.dtype == NullPointer;
    case Const:
        if (to.isRef) {
            throw new CompilerError(location, "cannot pass a const value as a ref parameter.");
        }
        return canImplicitCast(location, from.getBase(), to) && !hasMutableIndirection(to);
    case Immutable:
        if (to.isRef) {
            throw new CompilerError(location, "cannot pass a immutable value as a ref parameter.");
        }
        return canImplicitCast(location, from.getBase(), to) && !hasMutableIndirection(to);
    default:
        return false;
    }
}

// incomplete
bool hasMutableIndirection(Type t)
{
    if (t.dtype == DType.Class || t.dtype == DType.Array || t.dtype == DType.Pointer) {
        return true;
    }
    return false;
}
