/**
 * Copyright 2010 Jakob Ovrum.
 * Copyright 2012 Bernard Helyer.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.enumeration;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;

class EnumDeclaration : Node
{
    Identifier name; // Optional - when absent, enum is anonymous
    Type base; // Optional
    EnumMemberList memberList;
}

// This exists so the member list has a unique location that spans braces and all members.
class EnumMemberList : Node
{
    EnumMember[] members;
}

class EnumMember : Node
{
    Identifier name;
    ConditionalExpression initialiser; // Optional
    Type type; // Optional, only allowed for manifest constants
}
