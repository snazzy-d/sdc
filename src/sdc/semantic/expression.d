/**
 * Copyright 2010 Bernard Helyer
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.semantic.expression;

import sdc.semantic.base;


class Expression : SemanticNode
{
    Temporary temporary;
}


class CommaExpression : Expression
{
    Expression parent;
}

class AssignExpression : Expression
{
    CommaExpression parent;
}

class ConditionalExpression : Expression
{
    AssignExpression parent;
}

class LogicalOrExpression : Expression
{
    ConditionalExpression parent;
}

class LogicalAndExpression : Expression
{
    LogicalOrExpression parent;
}

class OrExpression : Expression
{
    LogicalAndExpression parent;
}

class XorExpression : Expression
{
    OrExpression parent;
}

class AndExpression : Expression
{
    XorExpression parent;
}

class CmpExpression : Expression
{
    AndExpression parent;
}

class ShiftExpression : Expression
{
    CmpExpression parent;
}

class AddExpression : Expression
{
    ShiftExpression parent;
}

class MulExpression : Expression
{
    AddExpression parent;
}

class PowExpression : Expression
{
    MulExpression parent;
}

class UnaryExpression : Expression
{
    PowExpression parent;
}

class PostfixExpression : Expression
{
    UnaryExpression parent;
}

class PrimaryExpression : Expression
{
    PostfixExpression parent;
}
