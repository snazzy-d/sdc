/**
 * Copyright 2010 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.sdcpragma;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.visitor;


// pragma \( Identifier , ArgumentList? \)
class Pragma : Node
{
    Identifier identifier;
    ArgumentList argumentList;  // Optional.

    override void accept(AstVisitor visitor)
    {
        identifier.accept(visitor);
        if (argumentList !is null) argumentList.accept(visitor);
        visitor.visit(this);
    }
}
