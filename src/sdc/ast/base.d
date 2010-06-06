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


class Node
{
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

class BasicType : Node
{
}

class Type : Node
{
}

class IntegerLiteral : Node
{
    Token token;
}

class FloatLiteral : Node
{
    Token token;
}

class CharacterLiteral : Node
{
    Token token;
}

class StringLiteral : Node
{
    Token token;
}

class ArrayLiteral : Node
{
    Token[] tokens;
}

class AssocArrayLiteral : Node
{
    Token[] tokens;
}

class FunctionLiteral : Node
{
}
