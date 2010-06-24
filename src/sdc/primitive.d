/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.primitive;

import std.conv;

import sdc.compilererror;
import sdc.ast.declaration;


struct Primitive
{
    int size;     /// Size of primitive in bytes.
    int pointer;  // 0 == not a pointer, 1 == pointer to iSize, 2 == pointer to pointer to iSize and so on.
}

enum ValueType { None, Variable, Constant }
abstract class Value
{
    ValueType type;
    Primitive primitive;
    PrimitiveTypeType dType = PrimitiveTypeType.Int;
}

class Variable : Value
{
    string name;
    
    this(string name, Primitive primitive)
    {
        type = ValueType.Variable;
        this.name = name;
        this.primitive = primitive;
    }
}

Variable voidVariable;

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



Primitive[PrimitiveTypeType] typeToPrimitive;

static this()
{
    with (PrimitiveTypeType) {
        typeToPrimitive[Bool] = Primitive(8, 0);
        typeToPrimitive[Byte] = Primitive(8, 0);
        typeToPrimitive[Ubyte] = Primitive(8, 0);
        typeToPrimitive[Short] = Primitive(16, 0);
        typeToPrimitive[Ushort] = Primitive(16, 0);
        typeToPrimitive[Int] = Primitive(32, 0);
        typeToPrimitive[Uint] = Primitive(32, 0);
        typeToPrimitive[Long] = Primitive(64, 0);
        typeToPrimitive[Ulong] = Primitive(64, 0);
        typeToPrimitive[Cent] = Primitive(128, 0);
        typeToPrimitive[Ucent] = Primitive(128, 0);
        typeToPrimitive[Char] = Primitive(8, 0);
        typeToPrimitive[Wchar] = Primitive(16, 0);
        typeToPrimitive[Dchar] = Primitive(32, 0);
        //Float
        //Double
        //Real
        //Ifloat
        //Idouble
        //Ireal
        //Cdouble
        //Creal
        //Void
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
