/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdl.d for more details.
 * 
 * ast/base.d: basic AST definitions.
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
    Identifier[] identifiers;
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
    Token token;
}

class CharacterLiteral : Literal
{
    Token token;
}

class StringLiteral : Literal
{
    Token token;
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
