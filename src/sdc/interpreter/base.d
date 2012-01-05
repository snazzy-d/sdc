/**
 * Copyright 2011 Bernard Helyer.
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


class Interpreter
{
    /// The last location this interpreter was called from.
    Location location;
    TranslationUnit translationUnit;
    
    this(TranslationUnit translationUnit)
    {
        this.translationUnit = translationUnit;
    }
    
    i.Value evaluate(Location location, Expression expr)
    {
        this.location = location;
        return interpretExpression(expr, this);
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

    abstract Value toBool();
    abstract Value add(Value);
    //Value sub(Value);
    //Value mul(Value);
    //Value div(Value);
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
    
    protected T binary(string OP)()
    {
        mixin("return cast(" ~ T.stringof ~ ")( val." ~ TypeToMember!T ~ OP ~ "val." ~ TypeToMember!T ~ ");");
    }
    
    override Value toBool()
    {
        return new BoolValue(mixin("cast(bool) val." ~ TypeToMember!T));
    }
    
    override Value add(Value v)
    {
        return new typeof(this)(binary!"+");
    }
}

alias SimpleValue!(int, DType.Int) IntValue;
alias SimpleValue!(bool, DType.Bool) BoolValue;

}  // struct i
