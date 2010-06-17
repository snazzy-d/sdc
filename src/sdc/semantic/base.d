/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.semantic.base;

import std.conv;

import sdc.tokenstream;


/**
 * Represents a temporary value.
 * The counters will be unique on the same thread.
 */
class Temporary
{
    static uint sCounter;
    
    /// Resets the counter for this thread.
    static void resetCounter()
    {
        sCounter = 0;
    }
    
    uint counter;
    
    this()
    {
        counter = sCounter;
        sCounter++;
    }
    
    override string toString()
    {
        return to!string(counter);
    }
}


class SemanticNode
{
}


class Module : SemanticNode
{
}




class Identifier : SemanticNode
{
    string value;
}

enum BaseType
{
    Bool = TokenType.Bool,
    Byte = TokenType.Byte,
    Ubyte = TokenType.Ubyte,
    Short = TokenType.Short,
    Ushort = TokenType.Ushort,
    Int = TokenType.Int,
    Uint = TokenType.Uint,
    Long = TokenType.Long,
    Ulong = TokenType.Ulong,
    Char = TokenType.Char,
    Wchar = TokenType.Wchar,
    Dchar = TokenType.Dchar,
    Float = TokenType.Float,
    Double = TokenType.Double,
    Real = TokenType.Real,
    Ifloat = TokenType.Ifloat,
    Idouble = TokenType.Idouble, 
    Ireal = TokenType.Ireal,
    Cfloat = TokenType.Cfloat,
    Cdouble = TokenType.Cdouble,
    Creal = TokenType.Creal,
    Void = TokenType.Void,
}

enum Type2
{
    Pointer,
    StaticArray,
    DynamicArray,
    AssociativeArray,
}

class Type : SemanticNode
{
    BaseType base;
    Type2[] type2s;
    
    override bool opEquals(Object o)
    {
        auto rhs = cast(Type) o;
        return rhs !is null && this.base == rhs.base && this.type2s == rhs.type2s;
    }
}



class Scope : SemanticNode
{
}

enum DeclarationExportType { Public, Private, Package }

class Declaration : SemanticNode
{
    DeclarationExportType exportType;
    Identifier identifier;
}


class FunctionDeclaration : Declaration
{
    Type returnValue;
    Parameter[] parameters;
}

class Parameter : SemanticNode
{
    Type type;
    Identifier identifier;
}


class VariableDeclaration : Declaration
{
    Type type;
}
