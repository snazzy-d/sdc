/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.aggregate;

import sdc.ast.base;


enum AggregateType
{
    Struct,
    Union
}

// ( struct | union ) identifier ( StructBody | ; )
class AggregateDeclaration : Node
{
    AggregateType type;
    Identifier name;
    StructBody structBody;  // Optional
}

// { StructBodyDeclaration* }
class StructBody : Node
{
    StructBodyDeclaration[] declarations;
}

enum StructBodyDeclarationType
{
    Declaration,
    StaticConstructor,
    StaticDestructor,
    Invariant,
    Unittest,
    StructAllocator,
    StructDeallocator,
    StructConstructor,
    StructPostblit,
    StructDestructor,
    AliasThis,
}

class StructBodyDeclaration : Node
{
    StructBodyDeclarationType type;
    Node node;
}
