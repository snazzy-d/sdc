/**
 * Copyright 2011-2012 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.interpreter.base;

import std.string;
import std.traits;

import sdc.aglobal;
import sdc.compilererror;
import sdc.location;
import sdc.util;
import sdc.ast.expression;
import sdc.gen.type;
import sdc.interpreter.expression;
import gen = sdc.gen.value;


class Interpreter
{
    /// The last location this interpreter was called from.
    Location location;
    TranslationUnit translationUnit;
    
    this(TranslationUnit translationUnit)
    {
        this.translationUnit = translationUnit;
    }
    
    i.Value call(Location location, Expression fn, Expression[] arguments)
    {
        throw new CompilerPanic(location, "CTFE is unimplemented.");
    }
    
    /// Convenience function for main driver.
    i.Value callMain()
    {
        throw new CompilerPanic("CTFE is unimplemented.");
    }
    
    i.Value evaluate(Location location, Expression expr)
    {
        this.location = location;
        return interpretExpression(expr, this);
    }
    
    i.Value evaluate(Location location, ConditionalExpression expr)
    {
        this.location = location;
        return interpretConditionalExpression(expr, this);
    }
}

struct i
{

abstract class Value
{
    union _val
    {
        bool Bool; 
        char Char;
        ubyte Ubyte;
        byte Byte;
        wchar Wchar;
        ushort Ushort;
        short Short;
        dchar Dchar;
        uint Uint;
        int Int;
        ulong Ulong;
        long Long;
        float Float;
        double Double;
        real Real;
        Value Pointer;
        Value[] Array;
    }
    DType type;
    _val val;
    
    /**
     * Create an i.Value of the given type.
     * 
     * Params:
     *   location = the source code location for diagnostic purposes.
     *   t = the type of i.Value to create.
     *   init = the value to pass to the i.Value's constructor.
     * Returns: the newly constructed value.
     * Throws: CompilerError if unable to construct the type.
     */
    static Value create(T)(Location location, Type t, T init)
    {
        switch (t.dtype) {
        case DType.Bool:
            return new i.BoolValue(cast(bool) init);
        case DType.Int:
            return new i.IntValue(cast(int) init);
        default:
            throw new CompilerError(location, "unable to create type at compile time.");
        }
    }
    
    abstract gen.Value toGenValue(gen.Module, Location);
    abstract Value toBool();
    abstract Value add(Value);
}

template TypeToMember(T)
{
    static if (is(T == bool)) enum TypeToMember = "Bool";
    else static if (is(T == char)) enum TypeToMember = "Char";
    else static if (is(T == ubyte)) enum TypeToMember = "Ubyte";
    else static if (is(T == byte)) enum TypeToMember = "Byte";
    else static if (is(T == wchar)) enum TypeToMember = "Wchar";
    else static if (is(T == ushort)) enum TypeToMember = "Ushort";
    else static if (is(T == short)) enum TypeToMember = "Short";
    else static if (is(T == dchar)) enum TypeToMember = "Dchar";
    else static if (is(T == uint)) enum TypeToMember = "Uint";
    else static if (is(T == int)) enum TypeToMember = "Int";
    else static if (is(T == ulong)) enum TypeToMember = "Ulong";
    else static if (is(T == long)) enum TypeToMember = "Long";
    else static if (is(T == float)) enum TypeToMember = "Float";
    else static if (is(T == double)) enum TypeToMember = "Double";
    else static if (is(T == real)) enum TypeToMember = "Real";
    else static if (isPointer!T) enum TypeToMember = "Pointer";
    else static if (isArray!T) enum TypeToMember = "Array";
    else static assert(false, "invalid type passed to TypeToMember.");
}

class SimpleValue(T, DType DTYPE) : Value
{
    this(T init)
    {
        mixin("val." ~ TypeToMember!T ~ " = init;");
        type = DTYPE;
    }
    
    protected T binary(string OP)(Value v)
    {
        return mixin("cast(" ~ T.stringof ~ ")( val." ~ TypeToMember!T ~ OP ~ "v.val." ~ TypeToMember!T ~ ")");
    }
    
    override gen.Value toGenValue(gen.Module mod, Location loc)
    {
        return new gen.IntValue(mod, loc, val.Int);
    }
    
    override Value toBool()
    {
        return new BoolValue(mixin("cast(bool) val." ~ TypeToMember!T));
    }
    
    override Value add(Value v)
    {
        return new typeof(this)(binary!"+"(v));
    }
}

alias SimpleValue!(int, DType.Int) IntValue;
alias SimpleValue!(bool, DType.Bool) BoolValue;

}  // struct i
