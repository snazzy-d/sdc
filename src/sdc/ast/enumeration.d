/**
 * Copyright 2010 Jakob Ovrum.
 * Copyright 2012 Bernard Helyer.
 * This file is part of SDC.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.enumeration;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;
import sdc.ast.visitor;

class EnumDeclaration : Node
{
    Identifier name; // Optional - when absent, enum is anonymous
    Type base; // Optional
    EnumMemberList memberList;

    override void accept(AstVisitor visitor)
    {
        if (name !is null) name.accept(visitor);
        if (base !is null) name.accept(visitor);
        memberList.accept(visitor);
        visitor.visit(this);
    }
}

// This exists so the member list has a unique location that spans braces and all members.
class EnumMemberList : Node
{
    EnumMember[] members;

    override void accept(AstVisitor visitor)
    {
        foreach (member; members) {
            member.accept(visitor);
            visitor.visit(this);
        }
    }
}

class EnumMember : Node
{
    Identifier name;
    ConditionalExpression initialiser; // Optional
    Type type; // Optional, only allowed for manifest constants

    override void accept(AstVisitor visitor)
    {
        name.accept(visitor);
        if (initialiser !is null) initialiser.accept(visitor);
        if (type !is null) type.accept(visitor);
        visitor.visit(this);
    }
}
