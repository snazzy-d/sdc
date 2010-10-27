/**
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.ast.enumeration;

import sdc.ast.base;
import sdc.ast.expression;
import sdc.ast.declaration;

enum EnumType
{
    Named,
    Anonymous
}

class EnumDeclaration : Node
{
    EnumType type;
    Identifier name; // Optional
    Type base;
    EnumMemberList memberList;
}

class EnumMemberList : Node
{
    EnumMember[] members;
}

class EnumMember : Node
{
    Identifier name;
    AssignExpression expression; // Optional
}
