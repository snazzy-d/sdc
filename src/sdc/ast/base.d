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
    Token token;
}
