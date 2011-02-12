/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.base;

import std.string;

import sdc.compilererror;
import sdc.tokenstream;
import sdc.location;


class Node
{
    Location location;
}

// ident(.ident)*
class QualifiedName : Node
{
    bool leadingDot = false;
    Identifier[] identifiers;
    
    QualifiedName dup()
    {
        auto qn = new QualifiedName();
        qn.identifiers = this.identifiers.dup;
        qn.leadingDot = this.leadingDot;
        return qn;
    }
}

class Identifier : Node
{
    string value;
}

class Literal : Node
{
}

class IntegerLiteral : Literal
{
    string value;
}

class FloatLiteral : Literal
{
    string value;
}

class CharacterLiteral : Literal
{
    string value;
}

class StringLiteral : Literal
{
    string value;
}

class ArrayLiteral : Literal
{
    Token[] tokens;
}

class AssocArrayLiteral : Literal
{
    Token[] tokens;
}

class FunctionLiteral : Literal
{
}
