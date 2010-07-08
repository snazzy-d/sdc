/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.primitive;

import std.conv;

import sdc.compilererror;
import sdc.gen.type;


struct Primitive
{
    int size;     /// Size of primitive in bytes.
    int pointer;  // 0 == not a pointer, 1 == pointer to iSize, 2 == pointer to pointer to iSize and so on.
    bool signed = true;
}

pure Primitive removePointer(Primitive primitive)
{
    return Primitive(primitive.size, primitive.pointer - 1, primitive.signed);
}

pure Primitive addPointer(Primitive primitive)
{
    return Primitive(primitive.size, primitive.pointer + 1, primitive.signed);
}

enum ValueType { None, Variable, Constant }
abstract class Value
{
    ValueType type;
    Primitive primitive;
    DType dtype;
}

class Variable : Value
{
    string name;
    bool isFunction;
    bool isGlobal;
    
    this(string name, Primitive primitive)
    {
        type = ValueType.Variable;
        this.name = name;
        this.primitive = primitive;
    }
}

__gshared Variable voidVariable;

static this()
{
    voidVariable = new Variable("VOID", Primitive(0, 0));
}

class Constant : Value
{
    string value;
    
    this(string value, Primitive primitive)
    {
        type = ValueType.Constant;
        this.value = value;
        this.primitive = primitive;
    }
}


string genVariableName(string s = "")
{
    static bool[string] sVariables;
    
    int counter = -1;
    string proposedVariable;
    do {
        counter++;
        proposedVariable = s ~ to!string(counter);
    } while (proposedVariable in sVariables);
    sVariables[proposedVariable] = true;
    
    return proposedVariable;
}


Variable genVariable(Primitive primitive, string s = "")
{
    auto name = genVariableName(s);
    return new Variable(name, primitive);
}


/*
Primitive[PrimitiveTypeType] typeToPrimitive;

static this()
{
    with (PrimitiveTypeType) {
        typeToPrimitive[Bool] = Primitive(1, 0, false);
        typeToPrimitive[Byte] = Primitive(8, 0, true);
        typeToPrimitive[Ubyte] = Primitive(8, 0, false);
        typeToPrimitive[Short] = Primitive(16, 0, true);
        typeToPrimitive[Ushort] = Primitive(16, 0, false);
        typeToPrimitive[Int] = Primitive(32, 0, true);
        typeToPrimitive[Uint] = Primitive(32, 0, false);
        typeToPrimitive[Long] = Primitive(64, 0, true);
        typeToPrimitive[Ulong] = Primitive(64, 0, false);
        typeToPrimitive[Cent] = Primitive(128, 0, true);
        typeToPrimitive[Ucent] = Primitive(128, 0, false);
        typeToPrimitive[Char] = Primitive(8, 0, false);
        typeToPrimitive[Wchar] = Primitive(16, 0, false);
        typeToPrimitive[Dchar] = Primitive(32, 0, false);
        //Float
        //Double
        //Real
        //Ifloat
        //Idouble
        //Ireal
        //Cdouble
        //Creal
        typeToPrimitive[Void] = Primitive(0, 0);
    }
}


Primitive fullTypeToPrimitive(Type type)
{
    if (type.type != TypeType.Primitive) {
        error(type.location, "non-primitive types are unimplemented");
    }
    auto primitive = cast(PrimitiveType) type.node;
    return typeToPrimitive[primitive.type];
}
*/
