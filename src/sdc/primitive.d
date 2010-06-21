/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.primitive;

import std.conv;


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

