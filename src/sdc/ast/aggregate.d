/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.aggregate;

import sdc.ast.base;
import sdc.ast.sdcmodule;
import sdc.ast.visitor;


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

    override void accept(AstVisitor visitor)
    {
        name.accept(visitor);
        structBody.accept(visitor);
        visitor.visit(this);
    }
}

// { StructBodyDeclaration* }
class StructBody : Node
{
    DeclarationDefinition[] declarations;

    override void accept(AstVisitor visitor)
    {
        foreach (decl; declarations) {
            decl.accept(visitor);
        }
        visitor.visit(this);
    }
}
