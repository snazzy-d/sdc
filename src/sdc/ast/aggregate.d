/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.aggregate;

import sdc.ast.base;
import sdc.ast.sdcmodule;


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
    DeclarationDefinition[] declarations;
}
